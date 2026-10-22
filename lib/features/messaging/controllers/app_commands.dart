import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/interaction_logic.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_commands.g.dart';

/// The slash commands members of a space can use: those of the bots that are
/// members there. Self-loads the first time it's watched and reloads on an
/// `application_commands.update` gateway event. `null` means "not loaded
/// yet".
@Riverpod(keepAlive: true)
class SpaceCommandsController extends _$SpaceCommandsController {
  @override
  List<AccordCommand>? build(String serverKey, String spaceId) {
    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) unawaited(_load(client));
    return null;
  }

  Future<void> _load(AccordClient client) async {
    final commands = (await client.interactions.commandsForSpace(
      spaceId,
    )).listOrLog<AccordCommand>('commands for $spaceId');
    if (!ref.mounted || !ref.isCurrentAccordClient(serverKey, client)) return;
    state = commands ?? const [];
  }

  /// Fetches the list again (a bot's commands changed).
  Future<void> reload(AccordClient client) => _load(client);
}

/// An interaction this client started and the application hasn't answered.
@immutable
class PendingInteraction {
  const PendingInteraction({
    required this.id,
    required this.channelId,
    this.commandName,
    this.messageId,
    this.customId,
    this.failed = false,
  });

  final String id;
  final String channelId;

  /// For a slash command: its name (shown in the message box).
  final String? commandName;

  /// For a component: the message and component it came from.
  final String? messageId;
  final String? customId;

  /// The application didn't answer in time.
  final bool failed;

  PendingInteraction asFailed() => PendingInteraction(
    id: id,
    channelId: channelId,
    commandName: commandName,
    messageId: messageId,
    customId: customId,
    failed: true,
  );
}

/// Interactions waiting for their application, keyed by interaction id. One
/// that gets no `interaction.success` within [interactionTimeout] turns
/// [PendingInteraction.failed] for a few seconds, then disappears.
@Riverpod(keepAlive: true)
class InteractionTracker extends _$InteractionTracker {
  final _timers = <String, Timer>{};

  /// Successes that arrived before the request that started them returned.
  final _early = <String>{};

  @override
  Map<String, PendingInteraction> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  void started(PendingInteraction pending) {
    if (_early.remove(pending.id)) return;
    state = {...state, pending.id: pending};
    _timers[pending.id]?.cancel();
    _timers[pending.id] = Timer(interactionTimeout, () => _fail(pending.id));
  }

  void succeeded(String id) {
    _timers.remove(id)?.cancel();
    if (!state.containsKey(id)) {
      _early.add(id);
      if (_early.length > 50) _early.remove(_early.first);
      return;
    }
    state = {...state}..remove(id);
  }

  void _fail(String id) {
    final pending = state[id];
    if (pending == null) return;
    state = {...state, id: pending.asFailed()};
    _timers[id] = Timer(const Duration(seconds: 5), () => dismiss(id));
  }

  void dismiss(String id) {
    _timers.remove(id)?.cancel();
    if (!state.containsKey(id)) return;
    state = {...state}..remove(id);
  }
}
