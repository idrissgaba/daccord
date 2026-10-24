import '../utils/json_utils.dart';

/// A user's voice connection state in a channel.
class AccordVoiceState {
  String userId;
  String? spaceId;
  String? channelId;
  String sessionId;
  bool deaf;
  bool mute;
  bool selfDeaf;
  bool selfMute;
  bool selfStream;
  bool selfVideo;
  bool suppress;

  /// When this stage audience member raised their hand, or null.
  String? requestToSpeakTimestamp;

  AccordVoiceState({
    this.userId = '',
    this.spaceId,
    this.channelId,
    this.sessionId = '',
    this.deaf = false,
    this.mute = false,
    this.selfDeaf = false,
    this.selfMute = false,
    this.selfStream = false,
    this.selfVideo = false,
    this.suppress = false,
    this.requestToSpeakTimestamp,
  });

  factory AccordVoiceState.fromJson(Map<String, dynamic> d) {
    return AccordVoiceState(
      userId: asString(d['user_id']),
        spaceId: asStringOrNull(d['space_id'] ?? d['guild_id']),
      channelId: asStringOrNull(d['channel_id']),
      sessionId: asString(d['session_id']),
      deaf: asBool(d['deaf']),
      mute: asBool(d['mute']),
      selfDeaf: asBool(d['self_deaf']),
      selfMute: asBool(d['self_mute']),
      selfStream: asBool(d['self_stream']),
      selfVideo: asBool(d['self_video']),
      suppress: asBool(d['suppress']),
      requestToSpeakTimestamp: asStringOrNull(d['request_to_speak_timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'user_id': userId,
      'session_id': sessionId,
      'deaf': deaf,
      'mute': mute,
      'self_deaf': selfDeaf,
      'self_mute': selfMute,
      'self_stream': selfStream,
      'self_video': selfVideo,
      'suppress': suppress,
    };
    if (spaceId != null) d['space_id'] = spaceId;
    if (channelId != null) d['channel_id'] = channelId;
    if (requestToSpeakTimestamp != null) {
      d['request_to_speak_timestamp'] = requestToSpeakTimestamp;
    }
    return d;
  }
}
