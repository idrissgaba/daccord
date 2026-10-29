import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/models/voice_connection.dart';
import 'package:bonfire/features/voice/services/afk_monitor.dart';
import 'package:bonfire/features/voice/services/global_key_watcher.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'package:bonfire/features/voice/models/voice_connection.dart';

part 'voice.g.dart';
part 'voice_afk.dart';
part 'voice_push_to_talk.dart';

/// Orchestrates voice channel join/leave and media toggles (reference:
/// `client_voice.gd`). Owns a single [VoiceSession] (the LiveKit transport) and
/// pushes runtime self-state to the server via `updateVoiceState`.
@Riverpod(keepAlive: true)
class VoiceController extends _$VoiceController with _VoiceAfk, _PushToTalk {
  @override
  VoiceSession? _session;

  /// The LiveKit session, exposed so the video grid can render its tracks.
  VoiceSession? get session => _session;

  /// Installs a stand-in session so tests can exercise the media toggles
  /// (mute/camera/screen share) without a native LiveKit room.
  @visibleForTesting
  set debugSession(VoiceSession? session) => _session = session;

  /// The local microphone level (0–1), for the mic-activity meter.
  double get localAudioLevel => _session?.localAudioLevel ?? 0;

  /// Whether the local mic is currently registering as speaking.
  bool get localIsSpeaking => _session?.localIsSpeaking ?? false;

  @override
  VoiceConnection build() {
    // Push live audio device/volume changes to the active session so the voice
    // settings page takes effect without a reconnect.
    ref.listen(
      settingsControllerProvider.select(
        (s) => (
          afkTimeoutMinutes: s.voiceAfkTimeoutMinutes,
          audioInputDeviceId: s.audioInputDeviceId,
          audioOutputDeviceId: s.audioOutputDeviceId,
          outputVolume: s.outputVolume,
          inputVolume: s.inputVolume,
          userVolumes: s.userVolumes,
          locallyMutedUsers: s.locallyMutedUsers,
          audio: voiceAudioOptionsOf(s),
        ),
      ),
      (prev, next) {
        if (prev?.afkTimeoutMinutes != next.afkTimeoutMinutes) {
          _syncAfk();
        }
        final session = _session;
        if (session == null || !state.isConnected) return;
        if (prev?.audioInputDeviceId != next.audioInputDeviceId) {
          session.setAudioInputDevice(next.audioInputDeviceId);
        }
        if (prev?.audioOutputDeviceId != next.audioOutputDeviceId) {
          session.setAudioOutputDevice(next.audioOutputDeviceId);
        }
        if (prev?.outputVolume != next.outputVolume) {
          session.setOutputVolume(next.outputVolume);
        }
        if (prev?.inputVolume != next.inputVolume) {
          session.setInputVolume(next.inputVolume);
        }
        if (prev?.userVolumes != next.userVolumes ||
            prev?.locallyMutedUsers != next.locallyMutedUsers) {
          session.setUserVolumes(
            _userVolumes(ref.read(settingsControllerProvider)),
          );
        }
        if (prev?.audio != next.audio) {
          session.setAudioOptions(next.audio);
        }
      },
    );
    ref.listen(settingsControllerProvider.select((s) => s.pushToTalk), (
      _,
      enabled,
    ) {
      _releasePushToTalk?.cancel();
      _session?.setPushToTalk(enabled);
      _syncGlobalPushToTalk();
    });
    ref.listen(
      settingsControllerProvider.select((s) => s.pushToTalkKey),
      (_, _) => _syncGlobalPushToTalk(),
    );
    listenSelf((prev, next) {
      if (prev?.isConnected != next.isConnected) _syncGlobalPushToTalk();
    });
    final keyHookAttached = _attachKeyHook();
    ref.onDispose(() {
      if (keyHookAttached) {
        HardwareKeyboard.instance.removeHandler(_onKeyEvent);
      }
      _globalKeys.stop();
      _releasePushToTalk?.cancel();
      _afkMonitor?.dispose();
      _afkMonitor = null;
      _session?.dispose();
      _session = null;
      soundManager.voiceSessionActive = false;
    });
    return const VoiceConnection();
  }

  /// Our per-participant volumes on the server this session is pinned to.
  Map<String, int> _userVolumes(AccordSettings settings) {
    final key = state.serverKey;
    return key == null ? const {} : settings.userVolumesFor(key);
  }

  /// The client for the connection our voice session is pinned to
  /// ([VoiceConnection.serverKey]), not the active one.
  AccordClient? get _client {
    final key = state.serverKey;
    if (key == null) return null;
    return ref.read(accordAuthProvider.notifier).clientForKey(key);
  }

  /// One-shot guard so a dropped connection triggers at most one proactive
  /// credential-refresh reconnect; reset whenever we (re)connect or leave.
  bool _reconnectAttempted = false;

  /// Serializes every session-mutating operation (join, leave, gateway-driven
  /// reconnect, forced disconnect) so a LiveKit `connect()` and `disconnect()`
  /// never overlap on the one reused [VoiceSession]. Otherwise a channel switch
  /// races the in-flight join against the server's gateway echoes, and the
  /// overlapping connect/teardown cycles wedge the WebRTC layer.
  Future<void> _queue = Future<void>.value();

  @override
  Future<void> _serialize(Future<void> Function() op) {
    final next = _queue.then((_) => op());
    // Keep the chain alive even if one op throws; the caller still sees the
    // error via [next].
    _queue = next.catchError((_) {});
    return next;
  }

  /// Joins the voice [channelId] in [spaceId]. Leaves any current channel
  /// first, fetches LiveKit credentials over REST, then connects the session.
  /// [spaceId] is null for DM/group-DM calls, which have no parent space.
  Future<void> join(String channelId, String? spaceId) async {
    // Joining is itself activity — never land in a channel already AFK.
    _ensureAfkMonitor().markActivity();
    await _serialize(() => _joinLocked(channelId, spaceId));
    _syncAfk();
  }

  @override
  Future<void> _joinLocked(String channelId, String? spaceId) async {
    if (state.channelId == channelId && !needsReconnect(state.sessionState)) {
      return;
    }
    if (state.isConnected) await _leaveLocked();

    // Pin to whichever connection is active *now* — the server whose channel
    // was tapped.
    final serverKey = ref.read(connectionsControllerProvider).activeKey;
    final client = serverKey == null
        ? null
        : ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
    if (client == null) {
      state = state.copyWith(error: 'No connection found');
      return;
    }

    _session ??= _buildSession();
    _reconnectAttempted = false;

    final result = await client.voice.join(
      channelId,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
    );
    final info = result.data;
    if (!result.ok || info is! AccordVoiceServerUpdate) {
      state = state.copyWith(
        error: voiceJoinErrorMessage(result.error?.message),
      );
      return;
    }
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      await client.voice.leave(channelId);
      state = state.copyWith(
        error: 'Voice backend unavailable — server returned no credentials',
      );
      return;
    }

    state = state.copyWith(
      channelId: channelId,
      spaceId: spaceId,
      serverKey: serverKey,
      sessionState: VoiceSessionState.connecting,
      clearError: true,
      serverMute: info.voiceState?.mute ?? false,
      serverDeaf: info.voiceState?.deaf ?? false,
      suppressed: info.voiceState?.suppress ?? false,
      stage: _isStage(serverKey, spaceId, channelId),
    );
    final settings = ref.read(settingsControllerProvider);
    // Flag the live call *before* the media session comes up, so no chime can
    // reconfigure the platform audio session underneath it.
    soundManager.voiceSessionActive = true;
    await _session!.connect(
      url,
      token,
      selfMute: state.selfMute || !state.canSpeak,
      selfDeaf: state.selfDeaf,
      relayOnly: settings.voiceRelayOnly,
      audioInputDeviceId: settings.audioInputDeviceId,
      audioOutputDeviceId: settings.audioOutputDeviceId,
      outputVolume: settings.outputVolume,
      inputVolume: settings.inputVolume,
      userVolumes: _userVolumes(settings),
      audio: voiceAudioOptionsOf(settings),
    );
    _applyConnectOutcome();
    if (state.sessionState == VoiceSessionState.failed) return;
    soundManager.play('voice_join');
    await _refreshVoiceStates(channelId);
  }

  /// After a (re)connect: report a failed media connection. If only microphone
  /// capture or publishing failed, we stay in the channel so you can listen,
  /// mark the mic as muted, tell the server, and surface the reason in the bar
  /// rather than showing a live mic that sends nothing (#325).
  void _applyConnectOutcome() {
    final connectionError = _session?.lastError;
    if (connectionError != null && state.isConnected) {
      soundManager.voiceSessionActive = false;
      state = state.copyWith(
        sessionState: VoiceSessionState.failed,
        error: connectionError,
      );
      return;
    }
    final micError = _session?.micError;
    if (micError == null || !state.isConnected || state.selfMute) return;
    state = state.copyWith(selfMute: true, error: micError);
    _sendVoiceStateUpdate();
  }

  /// Leaves the current voice channel and tears the session down.
  Future<void> leave() async {
    await _serialize(_leaveLocked);
    _syncAfk();
  }

  Future<void> _leaveLocked() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    _reconnectAttempted = false;
    await _session?.disconnect();
    soundManager.voiceSessionActive = false;
    await _client?.voice.leave(channelId);
    soundManager.play('voice_leave');
    state = const VoiceConnection();
  }

  void toggleMute() => setMute(!state.selfMute);

  void setMute(bool muted) {
    _afkMonitor?.markActivity();
    // Outside a call the choice is kept for the next join, as in other voice
    // chat apps.
    if (!state.isConnected) {
      state = state.copyWith(selfMute: muted);
      soundManager.play(muted ? 'mute' : 'unmute');
      return;
    }
    state = state.copyWith(selfMute: muted);
    soundManager.play(muted ? 'mute' : 'unmute');
    _sendVoiceStateUpdate();
    // Our own unmute still counts, but the mic stays off until the server
    // lets us speak again (see [applyServerFlags]).
    if (!muted && !state.canSpeak) {
      state = state.copyWith(error: state.speakBlockedReason);
      return;
    }
    final session = _session;
    if (session != null) unawaited(_applyMic(session, enabled: !muted));
  }

  /// Our own voice state changed on the server: a moderator muted or deafened
  /// us (or lifted it), or the channel's `speak` right changed. LiveKit already
  /// enforces it; this keeps the bar and the microphone in step.
  void applyServerFlags(AccordVoiceState vs) {
    if (!state.isConnected || vs.channelId != state.channelId) return;
    final couldSpeak = state.canSpeak;
    state = state.copyWith(
      serverMute: vs.mute,
      serverDeaf: vs.deaf,
      suppressed: vs.suppress,
    );
    final session = _session;
    if (session == null || couldSpeak == state.canSpeak) return;
    if (!state.canSpeak) {
      state = state.copyWith(error: state.speakBlockedReason);
      unawaited(session.setMicEnabled(false));
    } else if (!state.selfMute) {
      unawaited(_applyMic(session, enabled: true));
    }
  }

  /// Applies a mute toggle to the media session. An *unmute* that fails (the
  /// OS denied the mic, no capture device) is reverted so the bar doesn't show
  /// a live mic that isn't, and the reason is surfaced.
  Future<void> _applyMic(VoiceSession session, {required bool enabled}) async {
    final error = await session.setMicEnabled(enabled);
    if (!identical(session, _session) ||
        !enabled ||
        !state.isConnected ||
        state.selfMute) {
      return;
    }
    if (error == null) {
      if (state.error?.startsWith('Microphone ') ?? false) {
        state = state.copyWith(clearError: true);
      }
      return;
    }
    state = state.copyWith(selfMute: true, error: error);
    _sendVoiceStateUpdate();
  }

  void toggleDeafen() => setDeafen(!state.selfDeaf);

  void setDeafen(bool deafened) {
    _afkMonitor?.markActivity();
    if (!state.isConnected) {
      state = state.copyWith(selfDeaf: deafened);
      soundManager.play(deafened ? 'deafen' : 'undeafen');
      return;
    }
    _session?.setDeafened(deafened);
    state = state.copyWith(selfDeaf: deafened);
    soundManager.play(deafened ? 'deafen' : 'undeafen');
    _sendVoiceStateUpdate();
  }

  Future<void> toggleVideo() async {
    if (!state.isConnected) return;
    final enable = !state.selfVideo;
    if (enable) {
      final settings = ref.read(settingsControllerProvider);
      final (width, height) = settings.videoDimensions;
      await _session?.setCameraEnabled(
        true,
        width: width,
        height: height,
        fps: settings.videoFps,
        bitrate: settings.videoBitrate,
        deviceId: settings.videoInputDeviceId,
      );
    } else {
      await _session?.setCameraEnabled(false);
    }
    state = state.copyWith(selfVideo: enable);
    _sendVoiceStateUpdate();
  }

  /// Toggles screen sharing. When starting, [sourceId] selects a specific
  /// screen/window chosen from the desktop source picker (null = let the
  /// platform prompt). Quality comes from the *screen-share* settings, not the
  /// camera ones.
  Future<void> toggleScreenShare({String? sourceId}) async {
    if (!state.isConnected) return;
    final enable = !state.selfStream;
    if (enable) {
      final settings = ref.read(settingsControllerProvider);
      final (width, height) = settings.screenShareDimensions;
      // A cancelled picker or a failed capture leaves nothing shared: the
      // state must not say otherwise (the bar showed a green "sharing" button
      // and a phantom tile after dismissing the browser prompt).
      final started = await _session?.setScreenShareEnabled(
        true,
        sourceId: sourceId,
        width: width,
        height: height,
        fps: settings.screenShareFps,
        bitrate: settings.screenShareBitrate,
        motionPriority: settings.screenShareMotionPriority,
        withAudio: settings.screenShareAudio,
      );
      if (started != true) return;
    } else {
      await _session?.setScreenShareEnabled(false);
    }
    state = state.copyWith(selfStream: enable);
    soundManager.play(enable ? 'stream_start' : 'stream_stop');
    _sendVoiceStateUpdate();
  }

  /// Whether we are receiving [userId]'s screen share.
  bool isWatchingStream(String userId) =>
      _session?.isWatchingStream(userId) ?? false;

  /// Starts or stops receiving [userId]'s screen share.
  Future<void> setWatchingStream(String userId, bool watch) async {
    await _session?.setWatchingStream(userId, watch);
  }

  /// A peer in our channel went live or ended their stream.
  void _onRemoteStreamChanged(String userId, {required bool started}) {
    soundManager.play(started ? 'stream_start' : 'stream_stop');
  }

  /// Fresh LiveKit credentials arrived over the gateway. Reconnects only when
  /// the session has actually dropped ([needsReconnect]); serialized behind any
  /// in-flight join.
  void handleServerUpdate(AccordVoiceServerUpdate info, {String? serverKey}) {
    if (info.moved) {
      if (serverKey != null && serverKey != state.serverKey) return;
      _serialize(() => _followMoveLocked(info));
      return;
    }
    _serialize(() => _serverUpdateLocked(info));
  }

  /// A moderator moved us to another channel: reconnect to the new room with
  /// the credentials the server sent, without leaving voice on the server
  /// (it already moved us there).
  Future<void> _followMoveLocked(AccordVoiceServerUpdate info) async {
    if (!state.isConnected || info.channelId.isEmpty) return;
    if (!isMoveForUs(
      currentChannelId: state.channelId,
      fromChannelId: info.fromChannelId,
      toChannelId: info.channelId,
    )) {
      return;
    }
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;
    final flags = info.voiceState;
    state = state.copyWith(
      channelId: info.channelId,
      spaceId: info.spaceId.isEmpty ? null : info.spaceId,
      sessionState: VoiceSessionState.connecting,
      // Camera and screen share don't follow us into the new room.
      selfVideo: false,
      selfStream: false,
      serverMute: flags?.mute ?? false,
      serverDeaf: flags?.deaf ?? false,
      suppressed: flags?.suppress ?? false,
      stage: _isStage(
        state.serverKey,
        info.spaceId.isEmpty ? null : info.spaceId,
        info.channelId,
      ),
      clearError: true,
    );
    _reconnectAttempted = false;
    final settings = ref.read(settingsControllerProvider);
    await _session?.connect(
      url,
      token,
      selfMute: state.selfMute || !state.canSpeak,
      selfDeaf: state.selfDeaf,
      relayOnly: settings.voiceRelayOnly,
      audioInputDeviceId: settings.audioInputDeviceId,
      audioOutputDeviceId: settings.audioOutputDeviceId,
      outputVolume: settings.outputVolume,
      inputVolume: settings.inputVolume,
      userVolumes: _userVolumes(settings),
      audio: voiceAudioOptionsOf(settings),
    );
    _applyConnectOutcome();
    if (state.sessionState == VoiceSessionState.failed) return;
    soundManager.play('voice_join');
    await _refreshVoiceStates(info.channelId);
  }

  Future<void> _serverUpdateLocked(AccordVoiceServerUpdate info) async {
    if (!state.isConnected || state.channelId != info.channelId) return;
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;
    final sessionState = _session?.state;
    if (sessionState == null || !needsReconnect(sessionState)) return;
    final settings = ref.read(settingsControllerProvider);
    await _session?.connect(
      url,
      token,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      relayOnly: settings.voiceRelayOnly,
      audioInputDeviceId: settings.audioInputDeviceId,
      audioOutputDeviceId: settings.audioOutputDeviceId,
      outputVolume: settings.outputVolume,
      inputVolume: settings.inputVolume,
      userVolumes: _userVolumes(settings),
      audio: voiceAudioOptionsOf(settings),
    );
    _applyConnectOutcome();
  }

  /// The server removed us from voice (our gateway state's channel went null).
  /// [leftChannel] is the channel the null-echo reported leaving; the teardown
  /// only fires if we're *still* in it when this runs, since a channel switch's
  /// own echo queues behind the join to the new channel.
  void handleForcedDisconnect(String? leftChannel) {
    _serialize(() => _forcedDisconnectLocked(leftChannel));
  }

  Future<void> _forcedDisconnectLocked(String? leftChannel) async {
    if (!state.isConnected) return;
    if (leftChannel != null && state.channelId != leftChannel) return;
    _reconnectAttempted = false;
    await _session?.disconnect();
    soundManager.voiceSessionActive = false;
    state = const VoiceConnection();
    _syncAfk();
  }

  bool _isStage(String? serverKey, String? spaceId, String? channelId) {
    if (serverKey == null || spaceId == null) return false;
    return ref
            .read(accordChannelsControllerProvider(serverKey, spaceId))
            ?.firstWhereOrNull((c) => c.id == channelId)
            ?.type ==
        'stage';
  }

  VoiceSession _buildSession() => VoiceSession()
    ..onChanged = _onSessionChanged
    ..onTracksChanged = _onSessionTracksChanged
    ..onRemoteStreamChanged = _onRemoteStreamChanged
    ..onStateChanged = _onSessionStateChanged
    ..onDisconnected = _onSessionDisconnected
    ..setPushToTalk(ref.read(settingsControllerProvider).pushToTalk);

  /// High-frequency speaker churn (many times per second while anyone talks):
  /// only push a new state when the speaking set actually changed.
  void _onSessionChanged() {
    final speaking = _session?.speakingUserIds ?? const {};
    if (setEquals(speaking, state.speakingUserIds)) return;
    state = state.copyWith(speakingUserIds: speaking);
  }

  void _onSessionTracksChanged() {
    state = state.copyWith(tick: state.tick + 1);
  }

  /// Dismisses the transient voice error.
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }

  void _onSessionStateChanged(VoiceSessionState sessionState) {
    if (!state.isConnected) return;
    // A clean (re)connection re-arms the one-shot reconnect guard.
    if (sessionState == VoiceSessionState.connected) {
      _reconnectAttempted = false;
    }
    state = state.copyWith(sessionState: sessionState);
  }

  void _onSessionDisconnected({
    required bool intentional,
    bool removed = false,
  }) {
    if (!shouldAutoReconnect(
      intentional: intentional,
      stillConnected: state.isConnected,
      alreadyAttempted: _reconnectAttempted,
    )) {
      return;
    }
    if (removed) {
      // The server pulled us out of the room: a move or a disconnect is on its
      // way over the gateway. Give it a moment before falling back to a
      // reconnect, which would otherwise put us back where we were.
      state = state.copyWith(sessionState: VoiceSessionState.reconnecting);
      Future<void>.delayed(removedReconnectGrace, () {
        if (!state.isConnected) return;
        _serialize(_reconnectLocked);
      });
      return;
    }
    // LiveKit gave up its own retries. Rather than wait on a gateway push that
    // may never come, refresh credentials and reconnect; a concurrent
    // voice.server_update is safe because both paths share [_queue].
    state = state.copyWith(sessionState: VoiceSessionState.reconnecting);
    _serialize(_reconnectLocked);
  }

  /// Re-fetches LiveKit credentials over REST for the channel we're still in and
  /// reconnects the session. One attempt per drop (guarded by
  /// [_reconnectAttempted], re-armed on a successful connect).
  Future<void> _reconnectLocked() async {
    if (_reconnectAttempted || !state.isConnected) return;
    // A gateway server_update may have already reconnected us while this was
    // queued; don't tear a healthy session back down.
    if (_session?.state == VoiceSessionState.connected) return;
    final channelId = state.channelId!;
    final client = _client;
    if (client == null) return;
    _reconnectAttempted = true;

    final result = await client.voice.join(
      channelId,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
    );
    final info = result.data;
    if (!result.ok || info is! AccordVoiceServerUpdate) {
      state = state.copyWith(
        sessionState: VoiceSessionState.failed,
        error: 'Voice reconnect failed — could not refresh credentials',
      );
      return;
    }
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      state = state.copyWith(
        sessionState: VoiceSessionState.failed,
        error: 'Voice reconnect failed',
      );
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    await _session?.connect(
      url,
      token,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      relayOnly: settings.voiceRelayOnly,
      audioInputDeviceId: settings.audioInputDeviceId,
      audioOutputDeviceId: settings.audioOutputDeviceId,
      outputVolume: settings.outputVolume,
      inputVolume: settings.inputVolume,
      userVolumes: _userVolumes(settings),
      audio: voiceAudioOptionsOf(settings),
    );
    _applyConnectOutcome();
  }

  Future<void> _refreshVoiceStates(String channelId) async {
    final client = _client;
    final serverKey = state.serverKey;
    if (client == null || serverKey == null) return;
    final result = await client.voice.getStatus(channelId);
    final data = result.data;
    if (_client != client ||
        state.serverKey != serverKey ||
        !result.ok ||
        data is! List<AccordVoiceState>) {
      return;
    }
    ref
        .read(voiceStatesControllerProvider(serverKey).notifier)
        .seedChannel(channelId, data);
  }

  void _sendVoiceStateUpdate() {
    final channelId = state.channelId;
    if (channelId == null) return;
    // `spaceId` is null during a DM call; the server resolves the scope from
    // the channel.
    _client?.updateVoiceState(
      state.spaceId,
      channelId,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      selfVideo: state.selfVideo,
      selfStream: state.selfStream,
    );
  }
}
