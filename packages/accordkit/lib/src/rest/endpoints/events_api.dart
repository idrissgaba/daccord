import '../../models/scheduled_event.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// A space's scheduled events.
class EventsApi extends EndpointBase {
  EventsApi(super.rest);

  /// Coming up or under way, soonest first.
  Future<RestResult> list(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/events');
    return result.deserializeArray(AccordScheduledEvent.fromJson);
  }

  /// Creates an event; [data] holds `name`, `entity_type`, `start_time` and
  /// the optional fields (`image` as a `data:` URI).
  Future<RestResult> create(String spaceId, Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('POST', '/spaces/$spaceId/events', body: data);
    return result.deserialize(AccordScheduledEvent.fromJson);
  }

  /// Edits an event, or starts / ends / cancels it with `status`.
  Future<RestResult> update(
      String spaceId, String eventId, Map<String, dynamic> data) async {
    final result = await rest
        .makeRequest('PATCH', '/spaces/$spaceId/events/$eventId', body: data);
    return result.deserialize(AccordScheduledEvent.fromJson);
  }

  Future<RestResult> delete(String spaceId, String eventId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/events/$eventId');
  }

  /// Marks the signed-in member interested, or ([interested] false) not.
  Future<RestResult> setInterested(
      String spaceId, String eventId, bool interested) async {
    final result = await rest.makeRequest(
      interested ? 'PUT' : 'DELETE',
      '/spaces/$spaceId/events/$eventId/users/@me',
    );
    return result.deserialize(AccordScheduledEvent.fromJson);
  }

  /// The ids of the interested members.
  Future<RestResult> users(String spaceId, String eventId) {
    return rest.makeRequest('GET', '/spaces/$spaceId/events/$eventId/users');
  }
}
