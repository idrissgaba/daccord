import '../../models/webhook.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Incoming webhook management (needs `manage_webhooks`).
class WebhooksApi extends EndpointBase {
  WebhooksApi(super.rest);

  /// Every webhook of a space.
  Future<RestResult> listForSpace(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/webhooks');
    return result.deserializeArray(AccordWebhook.fromJson);
  }

  /// The webhooks posting in one channel.
  Future<RestResult> listForChannel(String channelId) async {
    final result =
        await rest.makeRequest('GET', '/channels/$channelId/webhooks');
    return result.deserializeArray(AccordWebhook.fromJson);
  }

  /// Creates a webhook in [channelId]; [avatar] is a `data:` URI.
  Future<RestResult> create(String channelId,
      {required String name, String? avatar}) async {
    final result = await rest.makeRequest(
      'POST',
      '/channels/$channelId/webhooks',
      body: {'name': name, if (avatar != null) 'avatar': avatar},
    );
    return result.deserialize(AccordWebhook.fromJson);
  }

  /// Renames, moves ([channelId]) or re-images ([avatar]: `data:` URI, or
  /// `''` to remove) a webhook.
  Future<RestResult> update(String webhookId,
      {String? name, String? channelId, String? avatar}) async {
    final result = await rest.makeRequest(
      'PATCH',
      '/webhooks/$webhookId',
      body: {
        if (name != null) 'name': name,
        if (channelId != null) 'channel_id': channelId,
        if (avatar != null) 'avatar': avatar,
      },
    );
    return result.deserialize(AccordWebhook.fromJson);
  }

  /// Deletes a webhook; its past messages stay.
  Future<RestResult> delete(String webhookId) {
    return rest.makeRequest('DELETE', '/webhooks/$webhookId');
  }
}
