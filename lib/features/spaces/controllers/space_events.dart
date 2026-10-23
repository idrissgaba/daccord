import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/spaces/utils/event_logic.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'space_events.g.dart';

/// A space's scheduled events that are coming up or under way, live first
/// then soonest first. Self-loads the first time it's watched and is kept in
/// sync by `scheduled_event.*` gateway events. `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class SpaceEventsController extends _$SpaceEventsController {
  @override
  List<AccordScheduledEvent>? build(String serverKey, String spaceId) {
    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) unawaited(_load(client));
    return null;
  }

  Future<void> _load(AccordClient client) async {
    final events = (await client.events.list(
      spaceId,
    )).listOrLog<AccordScheduledEvent>('events for $spaceId');
    if (!ref.mounted || !ref.isCurrentAccordClient(serverKey, client)) return;
    state = sortEvents(events ?? const []);
  }

  Future<void> reload(AccordClient client) => _load(client);

  /// Applies a created or updated event. A broadcast doesn't say whether we
  /// are interested, so the known answer is kept.
  void upsert(AccordScheduledEvent event) {
    final current = state ?? const <AccordScheduledEvent>[];
    final previous = current.where((e) => e.id == event.id).firstOrNull;
    final merged = event.interested == null && previous?.interested != null
        ? event.copyWith(interested: previous!.interested)
        : event;
    state = sortEvents([...current.where((e) => e.id != event.id), merged]);
  }

  void remove(String eventId) {
    final current = state;
    if (current == null) return;
    state = current.where((e) => e.id != eventId).toList();
  }

  /// Someone ([mine]: us) became interested, or stopped being.
  void applyInterest(
    String eventId, {
    required bool added,
    required bool mine,
  }) {
    final current = state;
    if (current == null) return;
    state = [
      for (final event in current)
        // Our own change already came back with the request's answer.
        if (event.id == eventId && !(mine && event.interested == added))
          event.copyWith(
            userCount: (event.userCount + (added ? 1 : -1)).clamp(0, 1 << 30),
            interested: mine ? added : event.interested,
          )
        else
          event,
    ];
  }
}
