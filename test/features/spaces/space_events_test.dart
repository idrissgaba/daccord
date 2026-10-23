import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/controllers/space_events.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/event_logic.dart';
import 'package:bonfire/features/spaces/views/space_events.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AccordScheduledEvent _event({
  String id = 'e1',
  String status = 'scheduled',
  String start = '2026-11-01T19:00:00+00:00',
  String? end,
  bool? interested,
  int users = 1,
  String type = 'voice',
}) => AccordScheduledEvent.fromJson({
  'id': id,
  'space_id': 's1',
  'name': 'Movie night',
  'entity_type': type,
  'status': status,
  'start_time': start,
  'end_time': end,
  'channel_id': type == 'voice' ? 'v1' : null,
  'location': type == 'voice' ? null : 'Park',
  'description': 'Popcorn, drinks; bring a blanket',
  'user_count': users,
  'interested': interested,
});

class _Events extends SpaceEventsController {
  _Events(this.events);
  final List<AccordScheduledEvent> events;
  @override
  List<AccordScheduledEvent>? build(String serverKey, String spaceId) =>
      sortEvents(events);
}

class _Channels extends AccordChannelsController {
  @override
  List<AccordChannel>? build(String serverKey, String spaceId) => [
    AccordChannel(id: 'v1', type: 'voice', name: 'Lounge'),
  ];
}

void main() {
  group('event logic', () {
    test('live events first, then soonest first; finished ones dropped', () {
      final sorted = sortEvents([
        _event(id: 'later', start: '2026-11-03T10:00:00+00:00'),
        _event(id: 'done', status: 'completed'),
        _event(id: 'soon', start: '2026-11-02T10:00:00+00:00'),
        _event(
          id: 'live',
          status: 'active',
          start: '2026-11-05T10:00:00+00:00',
        ),
      ]);
      expect(sorted.map((e) => e.id), ['live', 'soon', 'later']);
    });

    test('when labels read relative to today', () {
      final start = DateTime(2026, 11, 1, 20, 30);
      final event = _event(start: start.toUtc().toIso8601String());
      expect(eventWhenLabel(event, DateTime(2026, 11, 1, 9)), 'Today at 20:30');
      expect(
        eventWhenLabel(event, DateTime(2026, 10, 31, 9)),
        'Tomorrow at 20:30',
      );
      expect(
        eventWhenLabel(event, DateTime(2026, 10, 20)),
        'Sun 1 Nov at 20:30',
      );
      expect(
        eventWhenLabel(_event(status: 'active'), DateTime(2026)),
        'Live now',
      );
    });

    test('the form mirrors the server rules', () {
      final now = DateTime(2026, 11, 1, 12);
      final start = DateTime(2026, 11, 1, 20);
      String? error({
        String name = 'Party',
        bool voice = true,
        String? channel = 'v1',
        String? location,
        DateTime? begin,
        DateTime? end,
      }) => eventFormError(
        name: name,
        voice: voice,
        channelId: channel,
        location: location,
        start: begin ?? start,
        end: end,
        now: now,
      );
      expect(error(), isNull);
      expect(error(name: ' '), contains('name'));
      expect(error(channel: null), contains('voice channel'));
      expect(error(voice: false, channel: null), contains('where'));
      expect(error(voice: false, location: 'Park'), contains('end time'));
      expect(error(begin: DateTime(2026, 11, 1, 8)), contains('passed'));
      expect(error(end: DateTime(2026, 11, 1, 19)), contains('after'));
    });

    test('the payload is in UTC with the right fields', () {
      final payload = eventPayload(
        name: ' Picnic ',
        description: ' ',
        voice: false,
        location: ' Park ',
        start: DateTime.utc(2026, 11, 1, 10),
        end: DateTime.utc(2026, 11, 1, 12),
      );
      expect(payload['name'], 'Picnic');
      expect(payload['entity_type'], 'external');
      expect(payload['location'], 'Park');
      expect(payload.containsKey('channel_id'), isFalse);
      expect(payload['start_time'], '2026-11-01T10:00:00.000Z');
    });

    test('the calendar file is valid iCalendar', () {
      final ics = buildIcs(
        _event(end: '2026-11-01T22:00:00+00:00'),
        where: 'Lounge, voice',
        now: DateTime.utc(2026, 10, 23, 8),
      );
      expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
      expect(ics, contains('DTSTART:20261101T190000Z\r\n'));
      expect(ics, contains('DTEND:20261101T220000Z\r\n'));
      expect(ics, contains(r'DESCRIPTION:Popcorn\, drinks\; bring a blanket'));
      expect(ics, contains(r'LOCATION:Lounge\, voice'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      // Without an end it lasts an hour.
      expect(
        buildIcs(_event(), where: '', now: DateTime.utc(2026)),
        contains('DTEND:20261101T200000Z'),
      );
      expect(icsFileName(_event()), 'movie-night.ics');
    });
  });

  group('events controller', () {
    test('broadcasts keep our interest; our own echo is not counted twice', () {
      final container = ProviderContainer(
        overrides: [
          spaceEventsControllerProvider(
            'k',
            's1',
          ).overrideWith(() => _Events([_event(interested: true, users: 2)])),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(
        spaceEventsControllerProvider('k', 's1').notifier,
      );
      controller.upsert(_event(users: 3));
      var event = container
          .read(spaceEventsControllerProvider('k', 's1'))!
          .single;
      expect(event.interested, isTrue);
      expect(event.userCount, 3);

      controller.applyInterest('e1', added: true, mine: true);
      event = container.read(spaceEventsControllerProvider('k', 's1'))!.single;
      expect(event.userCount, 3, reason: 'already applied from our request');
      controller.applyInterest('e1', added: true, mine: false);
      event = container.read(spaceEventsControllerProvider('k', 's1'))!.single;
      expect(event.userCount, 4);
      controller.applyInterest('e1', added: false, mine: true);
      event = container.read(spaceEventsControllerProvider('k', 's1'))!.single;
      expect(event.interested, isFalse);
      expect(event.userCount, 3);
      controller.remove('e1');
      expect(container.read(spaceEventsControllerProvider('k', 's1')), isEmpty);
    });
  });

  testWidgets('the dialog lists events and toggles interest', (tester) async {
    final requests = <http.Request>[];
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    final client = AccordClient(
      token: 't',
      baseUrl: server.baseUrl,
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'data': _event(interested: true, users: 2).toJson()}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accordAuthProvider.overrideWithValue(
            AccordAuthLoggedIn(
              client: client,
              session: AccordSession(
                server: server,
                token: 't',
                userId: 'u-self',
                username: 'self',
              ),
            ),
          ),
          spacesControllerProvider.overrideWithValue([
            AccordSpace(id: 's1', ownerId: 'u-self'),
          ]),
          accordMembersControllerProvider('', 's1').overrideWithValue(const {}),
          accordChannelsControllerProvider(
            '',
            's1',
          ).overrideWith(_Channels.new),
          spaceEventsControllerProvider(
            '',
            's1',
          ).overrideWith(() => _Events([_event(interested: false)])),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: const Scaffold(body: SpaceEventsDialog(spaceId: 's1')),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Movie night'), findsOneWidget);
    expect(find.textContaining('Lounge'), findsOneWidget);
    expect(find.byKey(const Key('event-create')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('event-interested-e1')));
    await tester.pumpAndSettle();
    expect(requests.single.method, 'PUT');
    expect(
      requests.single.url.path,
      endsWith('/spaces/s1/events/e1/users/@me'),
    );
    expect(find.text('Interested'), findsOneWidget);
    expect(find.text('2 interested'), findsOneWidget);
  });
}
