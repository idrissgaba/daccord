import 'dart:async';

import 'package:bonfire/features/voice/services/android_screen_capture.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

/// Lifecycle of the LiveKit media connection, mirroring the reference client's
/// `ClientModels.VoiceSessionState`.
enum VoiceSessionState {
  connecting,
  connected,
  reconnecting,
  failed,
  disconnected,
}

/// Thin wrapper around a LiveKit [Room] that exposes the control surface the
/// [VoiceController] needs (reference: `livekit_adapter.gd`).
///
/// Participant identity equals the Accord user ID (the server sets it), so the
/// UI can match LiveKit participants to voice states directly.
class VoiceSession {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VoiceSessionState _state = VoiceSessionState.disconnected;
  String? _lastError;
  bool _deafened = false;
  bool _intentionalDisconnect = false;

  String? _micError;

  /// How long [_awaitLocalParticipant] waits before giving up on the initial
  /// mic publish.
  static const _localParticipantTimeout = Duration(seconds: 10);

  /// Output (remote-audio) gain as a 0–2 multiplier, applied to every remote
  /// audio track via the WebRTC track volume.
  double _outputGain = 1;

  /// Our local per-participant volumes (0–200 %, 0 = muted for us), keyed by
  /// participant identity (= Accord user ID). Absent users play at 100 %.
  Map<String, int> _userVolumes = const {};

  /// Input (microphone) gain as a 0–2 multiplier; best-effort — not every
  /// platform honours setting volume on a capture track.
  double _inputGain = 1;

  /// Microphone processing/quality preferences, applied to every capture.
  VoiceAudioOptions _audio = const VoiceAudioOptions();

  /// The selected microphone (null = system default), kept so a processing
  /// change restarts the capture on the same device.
  String? _inputDeviceId;

  /// Whether the user wants the mic live (i.e. not self-muted).
  bool _micWanted = false;

  /// Push-to-talk: the mic only transmits while [_pttPressed].
  bool _pushToTalk = false;
  bool _pttPressed = false;

  /// Local mic level (0–1) polled from the track's WebRTC `media-source`
  /// stats. [Participant.audioLevel] only updates from throttled server
  /// active-speaker reports, so the meter would lag on quiet input.
  double _localInputLevel = 0;
  Timer? _levelTimer;
  bool _pollingLevel = false;

  /// Fires on high-frequency room churn (active-speaker / audio-level reports),
  /// many times per second while anyone talks, so handlers must stay cheap.
  VoidCallback? onChanged;

  /// Fires only when the renderable track/participant set changes, so the video
  /// grid rebuilds on structural changes rather than on every speaker report.
  VoidCallback? onTracksChanged;

  /// Fires when the session transitions to a new lifecycle [state].
  void Function(VoiceSessionState state)? onStateChanged;

  /// Fires when the room disconnects. [intentional] is true for a local
  /// leave/teardown, false for a dropped connection.
  void Function({required bool intentional, bool removed})? onDisconnected;

  Room? get room => _room;
  VoiceSessionState get state => _state;
  String? get lastError => _lastError;

  /// Why the microphone is *not* live after the last [connect] (or the last
  /// [setMicEnabled] `true`): access denied, no capture device, or a failed
  /// publish. Null when the mic was published or wasn't requested.
  String? get micError => _micError;

  /// Our published camera track (null when the camera is off).
  VideoTrack? get localCameraTrack =>
      _videoTrackOf(_room?.localParticipant, TrackSource.camera);

  /// Our published screen-share track (null when not sharing).
  VideoTrack? get localScreenTrack =>
      _videoTrackOf(_room?.localParticipant, TrackSource.screenShareVideo);

  /// A remote participant's camera track, or null when they have none.
  VideoTrack? remoteCameraTrack(String userId) =>
      _videoTrackOf(_remoteByIdentity(userId), TrackSource.camera);

  /// A remote participant's screen-share track, or null when they aren't
  /// sharing (or it hasn't been subscribed yet).
  VideoTrack? remoteScreenTrack(String userId) =>
      _videoTrackOf(_remoteByIdentity(userId), TrackSource.screenShareVideo);

  Participant? _remoteByIdentity(String userId) {
    final room = _room;
    if (room == null || userId.isEmpty) return null;
    for (final p in room.remoteParticipants.values) {
      if (p.identity == userId) return p;
    }
    return null;
  }

  VideoTrack? _videoTrackOf(Participant? participant, TrackSource source) {
    if (participant == null) return null;
    for (final pub in participant.videoTrackPublications) {
      // A muted track (camera turned off) has no frames: show the avatar.
      if (pub.source == source && !pub.muted) {
        final track = pub.track;
        if (track is VideoTrack) return track;
      }
    }
    return null;
  }

  /// User IDs (participant identities) currently speaking.
  Set<String> get speakingUserIds {
    final room = _room;
    if (room == null) return const {};
    final participants = <Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];
    return {
      for (final p in participants)
        if (p.isSpeaking && p.identity.isNotEmpty) p.identity,
    };
  }

  /// Our local microphone level (0–1) for the mic-activity meter; zero while
  /// silent or muted.
  double get localAudioLevel => _localInputLevel;

  /// Whether LiveKit's server active-speaker report counts us as speaking.
  bool get localIsSpeaking => _room?.localParticipant?.isSpeaking ?? false;

  /// Connects to [url] with [token], reusing the single long-lived [Room].
  ///
  /// Never recreate the [Room] per call: disposing the old one leaves its
  /// native WebRTC `PeerConnection` + mic capture half-released, so the next
  /// publish throws `TrackPublishException` / `No active stream to cancel`.
  /// The Room is soft-disconnected between connects and only released in
  /// [dispose].
  Future<void> connect(
    String url,
    String token, {
    bool selfMute = false,
    bool selfDeaf = false,
    bool relayOnly = false,
    String? audioInputDeviceId,
    String? audioOutputDeviceId,
    int outputVolume = 100,
    int inputVolume = 100,
    Map<String, int>? userVolumes,
    VoiceAudioOptions? audio,
  }) async {
    _deafened = selfDeaf;
    _micWanted = !selfMute;
    _outputGain = voiceGain(outputVolume);
    _inputGain = voiceGain(inputVolume);
    if (userVolumes != null) _userVolumes = userVolumes;
    if (audio != null) _audio = audio;

    final captureDeviceId = normalizeDeviceId(audioInputDeviceId);
    _inputDeviceId = captureDeviceId;
    final room = _ensureRoom();

    // `_intentionalDisconnect` stays set until the new connection is up, so the
    // RoomDisconnectedEvent this triggers doesn't auto-reconnect.
    _intentionalDisconnect = true;
    if (room.connectionState != ConnectionState.disconnected) {
      _stopLevelPolling();
      await _stopLocalMedia();
      try {
        await room.disconnect();
      } catch (e) {
        debugPrint('LiveKit pre-connect disconnect error: $e');
      }
    }

    _setState(VoiceSessionState.connecting);
    _lastError = null;
    _micError = null;

    // Capture the mic before joining so the OS prompt appears at join and a
    // denied capture surfaces as [micError] instead of a silently skipped
    // publish.
    LocalAudioTrack? micTrack;
    if (!selfMute) {
      try {
        micTrack = await LocalAudioTrack.create(
          _audio.captureOptions(captureDeviceId),
        );
      } catch (e) {
        _micError = describeMicFailure(e);
        debugPrint('LiveKit mic capture failed: $e');
      }
    }

    try {
      await room.connect(
        url,
        token,
        connectOptions: voiceConnectOptions(relayOnly),
      );
      _intentionalDisconnect = false;
      if (micTrack != null) {
        // Ownership moves to the publication (or is released on failure).
        final track = micTrack;
        micTrack = null;
        await _publishMic(room, track);
      }
      if (selfDeaf) await _applyDeafen(true);
      await _applyTransmitGate();
      await _applyOutputDevice(audioOutputDeviceId);
      await _applyOutputGain();
      await _applyInputGain();
      _startLevelPolling();
      _setState(VoiceSessionState.connected);
    } catch (e) {
      _lastError = relayOnly
          ? 'Relay-only voice could not connect. The server needs a reachable '
                'TURN relay. Check the server configuration or turn off relay-only '
                'voice in Voice & Video settings. ($e)'
          : '$e';
      debugPrint('LiveKit connect failed: $e');
      await _releaseTrack(micTrack);
      await disconnect();
      // Cleanup emits a disconnected event. Preserve the failed outcome after
      // it finishes so the UI keeps the reason the join failed.
      _setState(VoiceSessionState.failed);
    }
  }

  /// Publishes the pre-captured microphone [track]; a failure is recorded in
  /// [micError] and the track released.
  Future<void> _publishMic(Room room, LocalAudioTrack track) async {
    try {
      final participant = await _awaitLocalParticipant(room);
      await participant.publishAudioTrack(
        track,
        publishOptions: _audio.publishOptions,
      );
    } catch (e) {
      _micError = describeMicFailure(e);
      debugPrint('LiveKit mic publish failed: $e');
      await _releaseTrack(track);
    }
  }

  /// `Room.connect` can resolve before the async join-response listener has
  /// created the local participant, which is only guaranteed once
  /// `RoomConnectedEvent` fires; wait for it rather than skip the publish.
  Future<LocalParticipant> _awaitLocalParticipant(Room room) async {
    final existing = room.localParticipant;
    if (existing != null) return existing;
    final listener = _listener;
    if (listener != null) {
      await listener.waitFor<RoomConnectedEvent>(
        duration: _localParticipantTimeout,
        onTimeout: () => throw TrackPublishException(
          'Timed out waiting for the room to finish connecting',
        ),
      );
    }
    final participant = room.localParticipant;
    if (participant == null) {
      throw TrackPublishException('Room connected without a local participant');
    }
    return participant;
  }

  /// Stops and disposes a local track we created but never published.
  Future<void> _releaseTrack(LocalTrack? track) async {
    if (track == null) return;
    await _guardMedia('release track', () async {
      await track.stop();
      await track.dispose();
    });
  }

  /// Lazily creates the one [Room] this session uses for its lifetime, wiring
  /// its listeners exactly once.
  Room _ensureRoom() {
    var room = _room;
    if (room != null) return room;
    room = Room();
    _room = room;
    room.addListener(_onRoomChanged);
    final listener = room.createListener();
    _listener = listener;
    _wireListener(listener);
    return room;
  }

  /// Stops any local capture so the native devices are released before we drop
  /// the socket. Each toggle is guarded: stopping an already-gone track throws
  /// "No active stream to cancel" on some platforms.
  Future<void> _stopLocalMedia() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    await _guardMedia(
      'stop screen share',
      () => participant.setScreenShareEnabled(false),
    );
    await releaseScreenCapture();
    await _guardMedia('stop camera', () => participant.setCameraEnabled(false));
    await _guardMedia(
      'stop mic',
      () => participant.setMicrophoneEnabled(false),
    );
  }

  /// Leaves the channel (local intent — no auto-reconnect) but keeps the
  /// [Room] alive for reuse.
  Future<void> disconnect() async {
    final room = _room;
    if (room == null) return;
    _intentionalDisconnect = true;
    _stopLevelPolling();
    await _stopLocalMedia();
    try {
      await room.disconnect();
    } catch (e) {
      debugPrint('LiveKit disconnect error: $e');
    }
  }

  /// Mutes or unmutes the microphone. An unmute with no published mic creates
  /// and publishes the track (raising the OS prompt on mobile if needed).
  ///
  /// Returns null once the mic is in the requested state, or the user-facing
  /// reason an *unmute* failed. Muting never fails.
  Future<String?> setMicEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null) return null;
    _micWanted = enabled;
    try {
      final hasMic =
          participant.getTrackPublicationBySource(TrackSource.microphone) !=
          null;
      if (enabled && !hasMic) {
        // First unmute of a call joined muted: publish it ourselves so the
        // processing and quality preferences apply (the SDK helper would use
        // its defaults).
        final track = await LocalAudioTrack.create(
          _audio.captureOptions(_inputDeviceId),
        );
        await participant.publishAudioTrack(
          track,
          publishOptions: _audio.publishOptions,
        );
      } else {
        await participant.setMicrophoneEnabled(
          enabled,
          audioCaptureOptions: _audio.captureOptions(_inputDeviceId),
        );
      }
      if (enabled) {
        _micError = null;
        // Unmuting restarts the capture track, which drops the applied gain.
        await _applyInputGain();
        // In push-to-talk mode an unmute only arms the mic; the key opens it.
        await _applyTransmitGate();
      }
      return null;
    } catch (e) {
      debugPrint('LiveKit mic toggle failed: $e');
      if (!enabled) return null;
      return _micError = describeMicFailure(e);
    }
  }

  /// Silences (or restores) every remote participant's audio locally by
  /// toggling the audio subscriptions.
  Future<void> setDeafened(bool deafened) async {
    _deafened = deafened;
    await _applyDeafen(deafened);
  }

  /// Enables (or disables) the camera. When enabling, [width]/[height]/[fps]/
  /// [bitrate] shape the capture via [CameraCaptureOptions] so the configured
  /// video-quality settings take effect, and [deviceId] selects the camera.
  Future<void> setCameraEnabled(
    bool enabled, {
    int? width,
    int? height,
    int? fps,
    int? bitrate,
    String? deviceId,
  }) async {
    CameraCaptureOptions? options;
    if (enabled && width != null && height != null) {
      options = CameraCaptureOptions(
        deviceId: normalizeDeviceId(deviceId),
        params: VideoParameters(
          dimensions: VideoDimensions(width, height),
          encoding: VideoEncoding(
            maxBitrate: bitrate ?? 1700000,
            maxFramerate: fps ?? 30,
          ),
        ),
      );
    }
    await _guardMedia(
      'camera',
      () => _room?.localParticipant?.setCameraEnabled(
        enabled,
        cameraCaptureOptions: options,
      ),
    );
  }

  /// Enables (or disables) screen sharing. When enabling, [sourceId] selects a
  /// specific screen or window (from the desktop source picker); a null/empty
  /// id falls back to the platform's own capture prompt. [width]/[height]/
  /// [fps]/[bitrate] shape both the capture and the *published encoding*;
  /// [motionPriority] decides what the encoder sacrifices first when it runs
  /// short of CPU/bandwidth.
  ///
  /// Capture options alone are not enough: without `VideoPublishOptions`,
  /// LiveKit falls back to its slide-oriented screen-share presets (720p caps
  /// at 800 kbps @ 5 fps, 1080p at 2.5 Mbps @ 15 fps), so we publish the track
  /// ourselves with an explicit `screenShareEncoding`.
  /// Returns whether the share is now in the requested state. Starting a
  /// share fails when the user cancels the platform picker (web
  /// `NotAllowedError`) or capture can't start; callers must not flip their
  /// own state on a false.
  Future<bool> setScreenShareEnabled(
    bool enabled, {
    String? sourceId,
    int? width,
    int? height,
    int? fps,
    int? bitrate,
    bool motionPriority = true,
    bool withAudio = false,
  }) async {
    final participant = _room?.localParticipant;
    if (participant == null) return false;

    if (!enabled) {
      await _guardMedia(
        'screen share',
        () => participant.setScreenShareEnabled(false),
      );
      await releaseScreenCapture();
      return true;
    }
    if (!await prepareScreenCapture()) return false;

    final resolvedFps = fps ?? defaultScreenShareFps;
    final resolvedBitrate = bitrate ?? defaultScreenShareBitrate;
    final dimensions = (width != null && height != null)
        ? VideoDimensions(width, height)
        : const VideoDimensions(1280, 720);
    final encoding = VideoEncoding(
      maxBitrate: resolvedBitrate,
      maxFramerate: resolvedFps,
    );
    final options = ScreenShareCaptureOptions(
      sourceId: (sourceId != null && sourceId.isNotEmpty) ? sourceId : null,
      maxFrameRate: resolvedFps.toDouble(),
      params: VideoParameters(dimensions: dimensions, encoding: encoding),
    );

    final published = await _guardMedia(
      'screen share',
      () => _publishScreenShare(
        participant,
        options: options,
        encoding: encoding,
        motionPriority: motionPriority,
        withAudio: withAudio,
      ),
    );
    if (!published) await releaseScreenCapture();
    return published;
  }

  /// Publishes the screen-share track with an explicit encoding.
  ///
  /// `LocalParticipant.setScreenShareEnabled` takes no publish options, so we
  /// create and publish the track directly to pass them. Two exceptions fall
  /// back to the SDK helper:
  ///  * iOS, where starting a share means activating the broadcast extension
  ///    (`BroadcastManager`) — logic that only lives inside the helper;
  ///  * an already-published share, where the helper's unmute path is correct.
  ///
  /// On the fallback paths we still tune the live sender afterwards, which is
  /// the one knob reachable post-publish.
  Future<void> _publishScreenShare(
    LocalParticipant participant, {
    required ScreenShareCaptureOptions options,
    required VideoEncoding encoding,
    required bool motionPriority,
    bool withAudio = false,
  }) async {
    // Games want frames; slides/code want pixels. LiveKit's own default for a
    // screen-share track is `maintainResolution`, i.e. exactly the wrong half
    // of that trade for the case this setting exists to fix.
    final degradation = motionPriority
        ? DegradationPreference.maintainFramerate
        : DegradationPreference.maintainResolution;

    final existing = participant.getTrackPublicationBySource(
      TrackSource.screenShareVideo,
    );
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (existing != null || isIOS) {
      await participant.setScreenShareEnabled(
        true,
        captureScreenAudio: withAudio,
        screenShareCaptureOptions: options,
      );
      await _applyScreenShareDegradation(participant, degradation);
      return;
    }

    // With audio, the platform capture prompt may also return the shared
    // tab/screen sound (desktop Chrome/Edge); elsewhere it is video only.
    final tracks = withAudio
        ? await LocalVideoTrack.createScreenShareTracksWithAudio(options)
        : <LocalTrack>[await LocalVideoTrack.createScreenShareTrack(options)];
    final track = tracks.whereType<LocalVideoTrack>().first;
    await participant.publishVideoTrack(
      track,
      publishOptions: VideoPublishOptions(
        screenShareEncoding: encoding,
        // One layer, all of the budget. Simulcast would split the bitrate
        // across a half-resolution duplicate and double the encode cost — a
        // bad trade when the whole point is sustaining 60 fps at full detail.
        simulcast: false,
        degradationPreference: degradation,
      ),
    );
    for (final audio in tracks.whereType<LocalAudioTrack>()) {
      await participant.publishAudioTrack(
        audio,
        publishOptions: screenShareAudioPublishOptions,
      );
    }
  }

  /// Applies [preference] to the published screen-share sender, for the paths
  /// where the track was published by the SDK helper rather than by us.
  Future<void> _applyScreenShareDegradation(
    LocalParticipant participant,
    DegradationPreference preference,
  ) async {
    final track = participant
        .getTrackPublicationBySource(TrackSource.screenShareVideo)
        ?.track;
    if (track is LocalVideoTrack) {
      await track.setDegradationPreference(preference);
    }
  }

  /// Switches the active microphone to [deviceId] (empty = system default),
  /// republishing the mic track so it takes effect mid-call.
  Future<void> setAudioInputDevice(String deviceId) async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    await _guardMedia('input device', () async {
      if (deviceId.isNotEmpty) await rtc.Helper.selectAudioInput(deviceId);
      _inputDeviceId = normalizeDeviceId(deviceId);
      final wasEnabled = participant.isMicrophoneEnabled();
      await participant.setMicrophoneEnabled(false);
      await participant.setMicrophoneEnabled(
        wasEnabled,
        audioCaptureOptions: _audio.captureOptions(_inputDeviceId),
      );
      await _applyInputGain();
    });
  }

  /// Switches the speaker/output device (empty = default). Only meaningful
  /// where `canPickAudioOutputDevice` is true — i.e. everywhere but iOS and
  /// web, which is where the settings page offers the picker.
  Future<void> setAudioOutputDevice(String deviceId) =>
      _applyOutputDevice(deviceId);

  /// Applies new microphone processing/quality preferences. Processing changes
  /// restart the live capture at once; the bitrate is a publish-time setting,
  /// so [VoiceAudioOptions.highQuality] takes effect from the next join.
  Future<void> setAudioOptions(VoiceAudioOptions audio) async {
    if (audio == _audio) return;
    _audio = audio;
    final track = _localMicTrack;
    if (track is LocalAudioTrack) {
      await _guardMedia(
        'audio processing',
        () => track.restartTrack(audio.captureOptions(_inputDeviceId)),
      );
      await _applyInputGain();
    }
  }

  /// Switches push-to-talk on or off. On, the mic stays closed until
  /// [setPushToTalkPressed]`(true)`; off, it follows the mute state again.
  Future<void> setPushToTalk(bool enabled) async {
    _pushToTalk = enabled;
    _pttPressed = false;
    await _applyTransmitGate();
  }

  /// The push-to-talk key (or button) went down / up.
  Future<void> setPushToTalkPressed(bool pressed) async {
    if (_pttPressed == pressed) return;
    _pttPressed = pressed;
    await _applyTransmitGate();
  }

  /// Opens or closes the published mic for push-to-talk without stopping the
  /// capture, so pressing the key transmits instantly. A self-muted mic is left
  /// alone: push-to-talk never overrides mute.
  Future<void> _applyTransmitGate() async {
    final track = _localMicTrack;
    if (track is! LocalAudioTrack || !_micWanted) return;
    final open = micTransmits(
      micWanted: _micWanted,
      pushToTalk: _pushToTalk,
      pttPressed: _pttPressed,
    );
    await _guardMedia(
      'push-to-talk',
      () => open
          ? track.unmute(stopOnMute: false)
          : track.mute(stopOnMute: false),
    );
  }

  /// Sets the remote-audio output volume from a 0–200 percentage.
  Future<void> setOutputVolume(int percent) async {
    _outputGain = voiceGain(percent);
    await _applyOutputGain();
  }

  /// Replaces our per-participant volumes ([userVolumes]: user ID → 0–200 %,
  /// 0 = muted for us) and re-applies every remote track's gain.
  Future<void> setUserVolumes(Map<String, int> userVolumes) async {
    _userVolumes = userVolumes;
    await _applyOutputGain();
  }

  /// Sets the microphone input volume from a 0–200 percentage (best-effort).
  Future<void> setInputVolume(int percent) async {
    _inputGain = voiceGain(percent);
    await _applyInputGain();
  }

  Future<void> _applyOutputDevice(String? deviceId) async {
    if (deviceId == null || deviceId.isEmpty) return;
    await _guardMedia(
      'output device',
      () => rtc.Helper.selectAudioOutput(deviceId),
    );
  }

  Future<void> _applyOutputGain() async {
    final room = _room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      final gain = _gainFor(participant.identity);
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) await _setRemoteVolume(track, gain);
      }
    }
  }

  /// The gain for [userId]'s audio: global output × their own volume.
  double _gainFor(String userId) => participantGain(
    outputGain: _outputGain,
    userVolumePercent: _userVolumes[userId],
    maxGain: kIsWeb ? maxWebTrackGain : maxNativeTrackGain,
  );

  Future<void> _setRemoteVolume(Track track, double gain) async {
    if (track is RemoteAudioTrack) {
      await _guardMedia('volume', () => track.setVolume(gain));
    } else {
      await _setTrackVolume(track.mediaStreamTrack, gain);
    }
  }

  Future<void> _applyInputGain() async {
    final track = _localMicTrack;
    if (track != null) {
      await _setTrackVolume(track.mediaStreamTrack, _inputGain);
    }
  }

  void _startLevelPolling() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _pollInputLevel(),
    );
  }

  void _stopLevelPolling() {
    _levelTimer?.cancel();
    _levelTimer = null;
    _localInputLevel = 0;
  }

  Future<void> _pollInputLevel() async {
    if (_pollingLevel) return; // a previous getStats call is still in flight
    _pollingLevel = true;
    try {
      final track = _localMicTrack;
      if (track is LocalAudioTrack) {
        final stats = await track.getSenderStats();
        _localInputLevel = (stats?.audioSourceStats?.audioLevel ?? 0)
            .toDouble();
      } else {
        _localInputLevel = 0; // muted/unpublished — nothing to measure
      }
    } catch (_) {
      // Transient stats failures shouldn't disturb the meter.
    } finally {
      _pollingLevel = false;
    }
  }

  AudioTrack? get _localMicTrack {
    final participant = _room?.localParticipant;
    if (participant == null) return null;
    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.microphone) {
        final track = pub.track;
        if (track is AudioTrack) return track;
      }
    }
    return null;
  }

  Future<void> _setTrackVolume(rtc.MediaStreamTrack track, double gain) async {
    await _guardMedia('volume', () => rtc.Helper.setVolume(gain, track));
  }

  /// Runs a LiveKit media toggle, logging platform/plugin errors (e.g. "No
  /// active stream to cancel" when the OS already tore the capture down)
  /// instead of letting them crash the app. Returns whether [op] succeeded.
  Future<bool> _guardMedia(String what, Future<void>? Function() op) async {
    try {
      await op();
      return true;
    } catch (e) {
      debugPrint('LiveKit $what toggle failed: $e');
      return false;
    }
  }

  Future<void> _applyDeafen(bool deafened) async {
    final room = _room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        if (deafened) {
          await pub.disable();
        } else {
          await pub.enable();
        }
      }
    }
  }

  void _wireListener(EventsListener<RoomEvent> listener) {
    listener
      ..on<TrackSubscribedEvent>((e) async {
        if (e.publication.kind == TrackType.AUDIO) {
          // Keep new remote audio muted while deafened, else apply our gain.
          if (_deafened) {
            await e.publication.disable();
          } else {
            final track = e.track;
            if (track is AudioTrack) {
              await _setRemoteVolume(track, _gainFor(e.participant.identity));
            }
          }
        }
        onTracksChanged?.call();
      })
      ..on<TrackUnsubscribedEvent>((_) => onTracksChanged?.call())
      // A camera turned off and back on is muted/unmuted, not re-subscribed;
      // without these the tile kept showing the avatar until something else
      // changed.
      ..on<TrackMutedEvent>((_) => onTracksChanged?.call())
      ..on<TrackUnmutedEvent>((_) => onTracksChanged?.call())
      ..on<TrackPublishedEvent>((_) => onTracksChanged?.call())
      ..on<TrackUnpublishedEvent>((_) => onTracksChanged?.call())
      ..on<TrackStreamStateUpdatedEvent>((_) => onTracksChanged?.call())
      ..on<LocalTrackPublishedEvent>((_) => onTracksChanged?.call())
      ..on<LocalTrackUnpublishedEvent>((_) => onTracksChanged?.call())
      ..on<ParticipantConnectedEvent>((_) => onTracksChanged?.call())
      ..on<ParticipantDisconnectedEvent>((_) => onTracksChanged?.call())
      ..on<RoomDisconnectedEvent>((e) {
        final intentional =
            _intentionalDisconnect ||
            e.reason == DisconnectReason.clientInitiated;
        _setState(VoiceSessionState.disconnected);
        onDisconnected?.call(
          intentional: intentional,
          removed: e.reason == DisconnectReason.participantRemoved,
        );
      })
      ..on<RoomReconnectingEvent>((_) {
        _setState(VoiceSessionState.reconnecting);
      })
      ..on<RoomReconnectedEvent>((_) {
        _setState(VoiceSessionState.connected);
      });
  }

  void _onRoomChanged() => onChanged?.call();

  void _setState(VoiceSessionState next) {
    if (_state == next) return;
    _state = next;
    onStateChanged?.call(next);
  }

  /// Releases the room and listeners for good.
  Future<void> dispose() async {
    final room = _room;
    if (room == null) return;
    _intentionalDisconnect = true;
    _stopLevelPolling();
    await _stopLocalMedia();
    room.removeListener(_onRoomChanged);
    await _listener?.dispose();
    _listener = null;
    _room = null;
    try {
      await room.disconnect();
      await room.dispose();
    } catch (e) {
      debugPrint('LiveKit teardown error: $e');
    }
  }
}

/// Keep the policy explicit on every initial connection and reconnect.
ConnectOptions voiceConnectOptions(bool relayOnly) => ConnectOptions(
  rtcConfiguration: RTCConfiguration(
    iceTransportPolicy: relayOnly
        ? RTCIceTransportPolicy.relay
        : RTCIceTransportPolicy.all,
  ),
);
