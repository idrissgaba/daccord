/// Pure decision logic for the voice stack, extracted so it can be unit-tested
/// without a native LiveKit `Room`.
library;

import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/services/voice_session.dart'
    show VoiceSessionState;
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:livekit_client/livekit_client.dart'
    show AudioCaptureOptions, AudioEncoding, AudioPublishOptions;

/// Converts a 0–200% volume preference into a WebRTC gain multiplier (0.0–2.0),
/// clamping out-of-range input. Gain is applied per remote track; 100% is
/// unity.
double voiceGain(num volumePercent) =>
    (volumePercent / 100).clamp(0.0, 2.0).toDouble();

/// Highest gain a remote track gets on native platforms, where WebRTC scales
/// the decoded audio itself.
const double maxNativeTrackGain = 2.0;

/// Highest gain on the web, where remote audio plays through an
/// `HTMLAudioElement` whose `volume` cannot exceed 1.
const double maxWebTrackGain = 1.0;

/// The gain for one remote participant's audio: our global output gain times
/// that participant's own volume ([userVolumePercent], 100 when unset),
/// clamped to [maxGain]. Zero when they are muted for us.
double participantGain({
  required double outputGain,
  int? userVolumePercent,
  bool locallyMuted = false,
  double maxGain = maxNativeTrackGain,
}) {
  if (locallyMuted) return 0;
  final userGain = voiceGain(userVolumePercent ?? 100);
  return (outputGain * userGain).clamp(0.0, maxGain).toDouble();
}

/// Microphone processing and quality preferences for a voice session. The
/// processing flags ask the platform's WebRTC stack (where supported) to clean
/// up the capture; [highQuality] raises the Opus bitrate for music or
/// instruments.
class VoiceAudioOptions {
  const VoiceAudioOptions({
    this.noiseSuppression = true,
    this.echoCancellation = true,
    this.autoGainControl = true,
    this.highQuality = false,
  });

  final bool noiseSuppression;
  final bool echoCancellation;
  final bool autoGainControl;
  final bool highQuality;

  /// Bitrate used when [highQuality] is on (128 kbps, Opus stereo preset).
  static const AudioEncoding highQualityEncoding =
      AudioEncoding.presetMusicHighQualityStereo;

  /// Capture options for the microphone [deviceId] (null = system default).
  AudioCaptureOptions captureOptions(String? deviceId) => AudioCaptureOptions(
    deviceId: deviceId,
    noiseSuppression: noiseSuppression,
    echoCancellation: echoCancellation,
    autoGainControl: autoGainControl,
    // Voice isolation is the platform's aggressive noise filter; keep it tied
    // to noise suppression so turning that off really passes everything.
    voiceIsolation: noiseSuppression,
  );

  /// Bitrate for ordinary voice: 64 kbps Opus, what other voice chat apps
  /// default to. LiveKit's own default is its 24–32 kbps speech preset, which
  /// sounds noticeably muffled next to them.
  static const AudioEncoding voiceEncoding = AudioEncoding(maxBitrate: 64000);

  /// Publish options for the microphone track. Voice keeps DTX (silence costs
  /// nothing) and adds RED, which resends audio redundantly so lost packets
  /// don't cut words. High quality also disables DTX, which would otherwise
  /// cut the quiet passages of music.
  AudioPublishOptions get publishOptions => highQuality
      ? const AudioPublishOptions(encoding: highQualityEncoding, dtx: false)
      : const AudioPublishOptions(encoding: voiceEncoding, red: true);

  @override
  bool operator ==(Object other) =>
      other is VoiceAudioOptions &&
      other.noiseSuppression == noiseSuppression &&
      other.echoCancellation == echoCancellation &&
      other.autoGainControl == autoGainControl &&
      other.highQuality == highQuality;

  @override
  int get hashCode => Object.hash(
    noiseSuppression,
    echoCancellation,
    autoGainControl,
    highQuality,
  );
}

/// The microphone preferences stored in [settings].
VoiceAudioOptions voiceAudioOptionsOf(AccordSettings settings) =>
    VoiceAudioOptions(
      noiseSuppression: settings.voiceNoiseSuppression,
      echoCancellation: settings.voiceEchoCancellation,
      autoGainControl: settings.voiceAutoGainControl,
      highQuality: settings.voiceHighQualityAudio,
    );

/// Whether the microphone should transmit right now: the user hasn't muted
/// it, and in push-to-talk mode the key is held.
bool micTransmits({
  required bool micWanted,
  required bool pushToTalk,
  required bool pttPressed,
}) => micWanted && (!pushToTalk || pttPressed);

/// Delay before push-to-talk closes the mic after the key is released, so the
/// end of the last word isn't clipped.
const Duration pushToTalkReleaseDelay = Duration(milliseconds: 200);

/// Publish options for a screen share's sound: music bitrate in stereo and no
/// DTX, which would cut quiet passages of a video or game.
const AudioPublishOptions screenShareAudioPublishOptions = AudioPublishOptions(
  name: 'screen_share_audio',
  encoding: AudioEncoding.presetMusicHighQualityStereo,
  dtx: false,
);

/// Normalises a selected audio/video device id: a null or empty id means
/// "system default" and is represented as null (what the capture options
/// expect).
String? normalizeDeviceId(String? deviceId) =>
    (deviceId == null || deviceId.isEmpty) ? null : deviceId;

/// Frame rate used for a screen share when the caller doesn't pass one.
/// Matches `AccordSettings.defaultScreenShareFps`.
const int defaultScreenShareFps = 60;

/// Send-bitrate ceiling used for a screen share when the caller doesn't pass
/// one. Matches `AccordSettings.screenShareBitrate` at its 720p60 default.
const int defaultScreenShareBitrate = 3000000;

/// Whether the controller should attempt an auto-reconnect after a session
/// disconnect: only for an unintentional drop while we still believe we're
/// connected, and only once per drop (the one-shot guard, re-checked on the
/// serialized queue by `_reconnectLocked`).
bool shouldAutoReconnect({
  required bool intentional,
  required bool stillConnected,
  required bool alreadyAttempted,
}) => !intentional && stillConnected && !alreadyAttempted;

/// How long to wait after the server removes us from a LiveKit room before
/// reconnecting on our own: long enough for the gateway to say why (a move or
/// a disconnect).
const Duration removedReconnectGrace = Duration(seconds: 2);

/// Whether a move announced for [fromChannelId] to [toChannelId] applies to a
/// session in [currentChannelId]: we must still be where the move started, and
/// not already at its destination.
bool isMoveForUs({
  required String? currentChannelId,
  required String? fromChannelId,
  required String toChannelId,
}) {
  if (currentChannelId == null || currentChannelId == toChannelId) {
    return false;
  }
  return fromChannelId == null ||
      fromChannelId.isEmpty ||
      fromChannelId == currentChannelId;
}

/// Whether fresh credentials (token refresh / SFU move) should reconnect a
/// session in [state]: only once it has dropped, failed or is reconnecting, so
/// a healthy or still-connecting session isn't churned.
bool needsReconnect(VoiceSessionState state) =>
    state == VoiceSessionState.disconnected ||
    state == VoiceSessionState.failed ||
    state == VoiceSessionState.reconnecting;

/// How long after a click on a voice channel row a second click still counts as
/// a double-click (Discord's fast path: double-click joins). Deliberately a
/// touch longer than Material's 300ms so the gesture is forgiving — it's the
/// only join affordance that costs no extra pointer travel.
const Duration voiceDoubleTapWindow = Duration(milliseconds: 400);

/// Whether a click at [now] following a previous click at [lastTapAt] on the
/// same row should be treated as the join gesture.
///
/// The channel row detects this itself instead of adding an `onDoubleTap` to its
/// `InkWell`: with a double-tap recognizer in the arena Flutter delays every
/// single tap until the double-tap timer expires, which would make simply
/// *selecting* a channel feel laggy. Selection stays instant; the second click
/// joins.
bool isVoiceDoubleTap(DateTime? lastTapAt, DateTime now) =>
    lastTapAt != null &&
    !now.isBefore(lastTapAt) &&
    now.difference(lastTapAt) <= voiceDoubleTapWindow;

/// The voice-bar message shown when the microphone could not be captured
/// because the OS denied (or has not granted) microphone access.
const String micPermissionDeniedMessage =
    'Microphone access is unavailable — enable it in Settings';

/// Whether a failed microphone capture/publish was a *permission* failure, as
/// opposed to a device/transport problem.
///
/// The error surfaces differently per platform: iOS and web reject
/// `getUserMedia` with a DOMException named `NotAllowedError`
/// (`FlutterRTCMediaStream.m`, "step 10 Permission Failure"), Android's
/// `GetUserMediaImpl` fails with a `PermissionDenied`-style message, and
/// flutter_webrtc's Dart layer wraps both in a plain
/// `'Unable to getUserMedia: …'` string — so this matches on the message text
/// rather than on a type.
bool isMicPermissionError(Object error) {
  final text = '$error'.toLowerCase();
  return text.contains('notallowederror') ||
      text.contains('permissiondenied') ||
      text.contains('permission');
}

/// The user-facing message for a microphone that could not be published at
/// join/unmute time. A permission failure gets the actionable Settings hint;
/// anything else keeps the platform's reason so the voice bar says *why*.
String describeMicFailure(Object error) {
  if (isMicPermissionError(error)) return micPermissionDeniedMessage;
  final reason = '$error'.replaceFirst('Unable to getUserMedia: ', '').trim();
  return reason.isEmpty
      ? 'Microphone unavailable'
      : 'Microphone unavailable: $reason';
}

/// Why the server won't carry our voice right now (a moderator muted or
/// deafened us, or the channel denies `speak`), or null when it will.
String? voiceSpeakBlockedReason({
  required bool serverMute,
  required bool serverDeaf,
  required bool suppressed,
  bool stage = false,
}) {
  if (serverDeaf) return 'A moderator has deafened you.';
  if (serverMute) return 'A moderator has muted you.';
  if (suppressed && stage) return stageAudienceReason;
  if (suppressed) return "You don't have permission to speak in this channel.";
  return null;
}

/// The user-facing reason a voice join failed, from the server's error
/// [message] (null keeps the generic fallback).
String voiceJoinErrorMessage(String? message) => switch (message) {
  'channel_full' => 'This voice channel is full.',
  null || '' => 'Failed to join voice channel',
  _ => message,
};

/// A channel's `user_limit` as a number (the model keeps the raw JSON), or
/// null when unset or not a number.
int? voiceUserLimit(Object? raw) => switch (raw) {
  final int limit => limit,
  final num limit => limit.toInt(),
  final String limit => int.tryParse(limit),
  _ => null,
};

/// The occupancy shown beside a voice channel: `3` for an open channel with
/// people in it, `3/10` for a capped one (shown even when empty), or null.
String? voiceOccupancyLabel(int count, Object? userLimit) {
  final limit = voiceUserLimit(userLimit);
  if (limit != null && limit > 0) return '$count/$limit';
  return count > 0 ? '$count' : null;
}
