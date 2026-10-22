import '../utils/json_utils.dart';

/// An incoming webhook: a secret URL that posts into one channel as its own
/// bot user ([userId]).
class AccordWebhook {
  AccordWebhook({
    required this.id,
    required this.spaceId,
    required this.channelId,
    required this.userId,
    required this.name,
    this.creatorId,
    this.avatar,
    this.token,
    this.createdAt = '',
  });

  final String id;
  final String spaceId;
  final String channelId;
  final String userId;
  final String name;
  final String? creatorId;

  /// CDN path of the avatar, if any.
  final String? avatar;

  /// The URL secret; only sent to members who manage webhooks.
  final String? token;
  final String createdAt;

  /// The URL services post to, given the API base (`.../api/v1`).
  String? executeUrl(String apiBaseUrl) {
    final secret = token;
    if (secret == null || secret.isEmpty) return null;
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return '$base/webhooks/$id/$secret';
  }

  factory AccordWebhook.fromJson(Map<String, dynamic> d) => AccordWebhook(
        id: asString(d['id']),
        spaceId: asString(d['space_id']),
        channelId: asString(d['channel_id']),
        userId: asString(d['user_id']),
        name: asString(d['name']),
        creatorId: asStringOrNull(d['creator_id']),
        avatar: asStringOrNull(d['avatar']),
        token: asStringOrNull(d['token']),
        createdAt: asString(d['created_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'space_id': spaceId,
        'channel_id': channelId,
        'user_id': userId,
        'name': name,
        'creator_id': creatorId,
        'avatar': avatar,
        if (token != null) 'token': token,
        'created_at': createdAt,
      };
}
