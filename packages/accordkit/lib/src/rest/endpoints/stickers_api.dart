import '../../models/message.dart';
import '../../models/sticker.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// A space's stickers, and sending one.
class StickersApi extends EndpointBase {
  StickersApi(super.rest);

  Future<RestResult> list(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/stickers');
    return result.deserializeArray(AccordSticker.fromJson);
  }

  /// Uploads a sticker; [image] is a `data:` URI (PNG, GIF or WebP).
  Future<RestResult> create(
    String spaceId, {
    required String name,
    required String image,
    String? description,
    String? tags,
  }) async {
    final result =
        await rest.makeRequest('POST', '/spaces/$spaceId/stickers', body: {
      'name': name,
      'image': image,
      if (description != null) 'description': description,
      if (tags != null) 'tags': tags,
    });
    return result.deserialize(AccordSticker.fromJson);
  }

  Future<RestResult> update(String spaceId, String stickerId,
      {String? name, String? description, String? tags}) async {
    final result = await rest
        .makeRequest('PATCH', '/spaces/$spaceId/stickers/$stickerId', body: {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (tags != null) 'tags': tags,
    });
    return result.deserialize(AccordSticker.fromJson);
  }

  Future<RestResult> delete(String spaceId, String stickerId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/stickers/$stickerId');
  }

  /// Sends [stickerId] as a message in [channelId].
  Future<RestResult> send(String channelId, String stickerId,
      {String? replyTo}) async {
    final result = await rest.makeRequest(
      'POST',
      '/channels/$channelId/stickers/$stickerId',
      body: {if (replyTo != null) 'reply_to': replyTo},
    );
    return result.deserialize(AccordMessage.fromJson);
  }
}
