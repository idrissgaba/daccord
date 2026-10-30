import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/shared/components/app_lifecycle_ticker_mode.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  _Auth(this.auth);
  final AccordAuthLoggedIn auth;
  @override
  AccordAuthState build() => auth;
  @override
  AccordClient? clientForKey(String key) =>
      key == auth.session.key ? auth.client : null;
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

Map<String, Object> _message(String id, String timestamp, String content) => {
  'id': id,
  'channel_id': 'channel',
  'author_id': 'other',
  'content': content,
  'timestamp': timestamp,
};

void main() {
  testWidgets(
    'history shows a date line per day and NEW before the first unread',
    (tester) async {
      final server = AccordServer.fromBaseUrl('https://example.test');
      final client = AccordClient(
        baseUrl: server.baseUrl,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/messages')) {
            return http.Response(
              jsonEncode({
                'data': [
                  _message('40', '2026-01-12T09:00:00Z', 'fourth'),
                  _message('30', '2026-01-12T08:00:00Z', 'third'),
                  _message('20', '2026-01-11T12:00:00Z', 'second'),
                  _message('10', '2026-01-10T12:00:00Z', 'first'),
                ],
              }),
              200,
            );
          }
          return http.Response('{"data":[]}', 200);
        }),
      );
      final session = AccordSession(
        server: server,
        token: 'test',
        userId: 'self',
        username: 'Self',
      );
      final key = session.key;
      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWith(
            () => _Auth(AccordAuthLoggedIn(client: client, session: session)),
          ),
          settingsControllerProvider.overrideWith(_Settings.new),
        ],
      );
      addTearDown(() {
        accordVisibleChannel = null;
        container.dispose();
        client.dispose();
      });
      container.read(connectionsControllerProvider.notifier).register(session);
      container.read(connectionsControllerProvider.notifier).setActive(key);
      accordVisibleChannel = (serverKey: key, channelId: 'channel');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final reads = container.read(readStateControllerProvider(key).notifier);
      // Read through 20, then 40 arrives and the channel is opened: the ack
      // advances the cursor and remembers it stood at 20.
      reads.hydrate(const [
        ReadEntry(channelId: 'channel', lastMessageId: '20'),
      ]);
      reads.markRead('channel', messageId: '20');
      reads.receiveMessage('channel', '40');
      reads.markRead('channel', messageId: '40');
      expect(reads.readBefore('channel'), '20');

      tester.view.physicalSize = const Size(1000, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(AppThemePreset.dark),
            home: const AppLifecycleTickerMode(
              child: Scaffold(
                body: MessagePane(
                  channel: null,
                  channelId: 'channel',
                  spaceId: null,
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('first', findRichText: true), findsOneWidget);
      expect(find.text('fourth', findRichText: true), findsOneWidget);
      // Three days of history: 10, 11 and 12 January.
      expect(find.text('January 10, 2026'), findsOneWidget);
      expect(find.text('January 11, 2026'), findsOneWidget);
      expect(find.text('January 12, 2026'), findsOneWidget);
      // One NEW line, above "third" (the first message after 20).
      final newLine = find.byKey(const Key('new-messages-divider'));
      expect(newLine, findsOneWidget);
      expect(
        tester.getTopLeft(newLine).dy,
        lessThan(tester.getTopLeft(find.text('third', findRichText: true)).dy),
      );
      expect(
        tester.getTopLeft(newLine).dy,
        greaterThan(
          tester.getTopLeft(find.text('second', findRichText: true)).dy,
        ),
      );
    },
  );

  test('readBefore is dropped once an ack brings nothing new', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final reads = container.read(readStateControllerProvider('k').notifier);
    reads.markRead('c', messageId: '10');
    expect(reads.readBefore('c'), isNull);
    reads.markRead('c', messageId: '30');
    expect(reads.readBefore('c'), '10');
    reads.markRead('c', messageId: '30');
    expect(reads.readBefore('c'), isNull);
  });

  test('messageDayLabel names today, yesterday and older days', () {
    final now = DateTime(2026, 10, 30, 15);
    expect(messageDayLabel(DateTime(2026, 10, 30, 1), now: now), 'Today');
    expect(messageDayLabel(DateTime(2026, 10, 29, 23), now: now), 'Yesterday');
    expect(messageDayLabel(DateTime(2026, 10, 1), now: now), 'October 1, 2026');
  });
}
