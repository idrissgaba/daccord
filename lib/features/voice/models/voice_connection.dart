import 'package:accordkit/accordkit.dart' show AccordVoiceState;
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:flutter/foundation.dart';

/// The local user's voice-connection state. Distinct from the per-user
/// [AccordVoiceState] cache ([VoiceStatesController]): this tracks *our* session
/// — which channel we're in, the LiveKit media state, and our self-flags.
@immutable
class VoiceConnection {
  const VoiceConnection({
    this.channelId,
    this.spaceId,
    this.serverKey,
    this.sessionState = VoiceSessionState.disconnected,
    this.selfMute = false,
    this.selfDeaf = false,
    this.selfVideo = false,
    this.selfStream = false,
    this.speakingUserIds = const {},
    this.isAfk = false,
    this.error,
    this.tick = 0,
    this.serverMute = false,
    this.serverDeaf = false,
    this.suppressed = false,
    this.stage = false,
  });

  final String? channelId;
  final String? spaceId;

  /// The connection (`userId@baseUrl`) the voice session is pinned to — *not*
  /// whichever server is active. Every voice REST/gateway call routes through
  /// this key's client so switching servers mid-call doesn't send our
  /// leave/state updates to the wrong server.
  final String? serverKey;
  final VoiceSessionState sessionState;
  final bool selfMute;
  final bool selfDeaf;
  final bool selfVideo;

  /// Whether we're currently screen-sharing.
  final bool selfStream;
  final Set<String> speakingUserIds;

  /// Whether *we* have been idle long enough to count as away (see
  /// `AfkMonitor`); surfaced to other members by flipping our presence to
  /// `idle`.
  final bool isAfk;

  /// Transient error message for the voice bar (auto-dismissed by the UI).
  final String? error;

  /// Bumped when the set of renderable LiveKit tracks/participants changes; the
  /// video grid watches it to rebuild its tiles.
  final int tick;

  /// A moderator muted us (the server sends none of our audio).
  final bool serverMute;

  /// A moderator deafened us (the server sends us nothing, takes nothing).
  final bool serverDeaf;

  /// The channel denies us `speak` — or, on a stage, we're in the audience.
  final bool suppressed;

  /// The channel is a stage.
  final bool stage;

  bool get isConnected => channelId != null;

  /// Whether the server carries our microphone right now.
  bool get canSpeak => !(serverMute || serverDeaf || suppressed);

  /// Why we can't speak (see [canSpeak]), or null.
  String? get speakBlockedReason => voiceSpeakBlockedReason(
    serverMute: serverMute,
    serverDeaf: serverDeaf,
    suppressed: suppressed,
    stage: stage,
  );

  VoiceConnection copyWith({
    String? channelId,
    String? spaceId,
    String? serverKey,
    VoiceSessionState? sessionState,
    bool? selfMute,
    bool? selfDeaf,
    bool? selfVideo,
    bool? selfStream,
    Set<String>? speakingUserIds,
    bool? isAfk,
    String? error,
    bool clearError = false,
    int? tick,
    bool? serverMute,
    bool? serverDeaf,
    bool? suppressed,
    bool? stage,
  }) {
    return VoiceConnection(
      channelId: channelId ?? this.channelId,
      spaceId: spaceId ?? this.spaceId,
      serverKey: serverKey ?? this.serverKey,
      sessionState: sessionState ?? this.sessionState,
      selfMute: selfMute ?? this.selfMute,
      selfDeaf: selfDeaf ?? this.selfDeaf,
      selfVideo: selfVideo ?? this.selfVideo,
      selfStream: selfStream ?? this.selfStream,
      speakingUserIds: speakingUserIds ?? this.speakingUserIds,
      isAfk: isAfk ?? this.isAfk,
      error: clearError ? null : (error ?? this.error),
      tick: tick ?? this.tick,
      serverMute: serverMute ?? this.serverMute,
      serverDeaf: serverDeaf ?? this.serverDeaf,
      suppressed: suppressed ?? this.suppressed,
      stage: stage ?? this.stage,
    );
  }
}
