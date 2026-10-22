import '../../models/command.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Slash commands and message components, from a member's side.
class InteractionsApi extends EndpointBase {
  InteractionsApi(super.rest);

  /// The commands of the bots in a space.
  Future<RestResult> commandsForSpace(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/commands');
    return result.deserializeArray(AccordCommand.fromJson);
  }

  /// Runs a command; [options] are `{name, value}` pairs. The answer's
  /// `data['id']` is the interaction id.
  Future<RestResult> runCommand({
    required String channelId,
    required String commandId,
    List<Map<String, dynamic>> options = const [],
  }) {
    return rest.makeRequest('POST', '/interactions', body: {
      'type': 'application_command',
      'channel_id': channelId,
      'command_id': commandId,
      'data': {'options': options},
    });
  }

  /// Clicks a button ([values] null) or submits a select menu of a bot's
  /// message.
  Future<RestResult> useComponent({
    required String channelId,
    required String messageId,
    required String customId,
    List<String>? values,
  }) {
    return rest.makeRequest('POST', '/interactions', body: {
      'type': 'message_component',
      'channel_id': channelId,
      'message_id': messageId,
      'data': {
        'custom_id': customId,
        if (values != null) 'values': values,
      },
    });
  }
}
