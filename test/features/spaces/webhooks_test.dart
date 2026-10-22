import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/messaging/views/message_author_header.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/views/accord_webhooks.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _hook({String id = 'w1', String channel = 'c1'}) => {
  'id': id,
  'space_id': 's1',
  'channel_id': channel,
  'user_id': 'u-$id',
  'creator_id': 'u-self',
  'name': 'Sonarr',
  'avatar': null,
  'token': 'secret-$id',
  'created_at': '2026-10-22 12:00:00',
};

class _Auth extends AccordAuth {
  _Auth(this.loggedIn);
  final AccordAuthLoggedIn loggedIn;
  @override
  AccordAuthState build() => loggedIn;
  @override
  AccordClient? clientForKey(String key) => loggedIn.client;
}

class _Connections extends ConnectionsController {
  @override
  ConnectionsState build() => const ConnectionsState(activeKey: '');
}

class _Channels extends AccordChannelsController {
  @override
  List<AccordChannel>? build(String serverKey, String spaceId) => [
    AccordChannel(id: 'c1', type: 'text', name: 'alerts'),
    AccordChannel(id: 'v1', type: 'voice', name: 'Lounge'),
    AccordChannel(id: 'c2', type: 'announcement', name: 'news'),
  ];
}

void main() {
  group('webhook model', () {
    test('parses and builds the URL services post to', () {
      final hook = AccordWebhook.fromJson(_hook());
      expect(hook.name, 'Sonarr');
      expect(hook.channelId, 'c1');
      expect(
        hook.executeUrl('https://chat.example/api/v1/'),
        'https://chat.example/api/v1/webhooks/w1/secret-w1',
      );
      final withoutToken = AccordWebhook.fromJson({..._hook(), 'token': null});
      expect(withoutToken.executeUrl('https://chat.example/api/v1'), isNull);
    });

    test('a message carries the per-message webhook name', () {
      final message = AccordMessage.fromJson({
        'id': 'm',
        'channel_id': 'c1',
        'author_id': 'u-w1',
        'content': 'Episode grabbed',
        'webhook_id': 'w1',
        'webhook_author': {'name': 'Sonarr (4K)'},
      });
      expect(message.webhookId, 'w1');
      expect(message.webhookAuthorName, 'Sonarr (4K)');
      expect(message.toJson()['webhook_author'], {'name': 'Sonarr (4K)'});
    });

    test('only text and announcement channels take webhooks', () {
      final channels = [
        AccordChannel(id: 'a', type: 'text'),
        AccordChannel(id: 'b', type: 'voice'),
        AccordChannel(id: 'c', type: 'announcement'),
        AccordChannel(id: 'd', type: 'forum'),
      ];
      expect(webhookChannels(channels).map((c) => c.id), ['a', 'c']);
    });
  });

  testWidgets('an app author shows the APP badge', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: const Scaffold(
          body: MessageAuthorHeader(
            name: 'Sonarr',
            time: '12:00',
            appBadge: true,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('app-badge')), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);
  });

  group('webhooks dialog', () {
    late List<http.Request> requests;
    late List<Map<String, dynamic>> hooks;

    Widget host() {
      requests = [];
      final server = AccordServer.fromBaseUrl('https://chat.example');
      final client = AccordClient(
        token: 't',
        tokenType: 'Bearer',
        baseUrl: server.baseUrl,
        gatewayUrl: server.gatewayUrl,
        cdnUrl: server.cdnUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          Object? body;
          if (request.method == 'GET' && path.endsWith('/spaces/s1/webhooks')) {
            body = {'data': hooks};
          } else if (request.method == 'POST' &&
              path.endsWith('/channels/c2/webhooks')) {
            final created = _hook(id: 'w2', channel: 'c2');
            hooks = [...hooks, created];
            body = {'data': created};
          } else if (request.method == 'DELETE') {
            hooks = hooks
                .where((h) => !path.endsWith('/webhooks/${h['id']}'))
                .toList();
            body = {'data': null};
          } else {
            body = {'data': null};
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final loggedIn = AccordAuthLoggedIn(
        client: client,
        session: AccordSession(
          server: server,
          token: 't',
          userId: 'u-self',
          username: 'self',
        ),
      );
      return ProviderScope(
        overrides: [
          accordAuthProvider.overrideWith(() => _Auth(loggedIn)),
          connectionsControllerProvider.overrideWith(_Connections.new),
          accordChannelsControllerProvider(
            '',
            's1',
          ).overrideWith(_Channels.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: const Scaffold(body: AccordWebhooksDialog(spaceId: 's1')),
        ),
      );
    }

    testWidgets('lists, creates, copies and deletes webhooks', (tester) async {
      hooks = [_hook()];
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Sonarr'), findsOneWidget);
      expect(find.text('#alerts'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('webhook-copy-w1')));
      await tester.pumpAndSettle();
      expect(copied, 'https://chat.example/api/v1/webhooks/w1/secret-w1');

      // Voice channels aren't offered.
      await tester.tap(find.byKey(const Key('webhook-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('webhook-channel-v1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('webhook-channel-c2')));
      await tester.pumpAndSettle();
      expect(find.text('#news'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('webhook-menu-w1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(
        requests.where((r) => r.method == 'DELETE').single.url.path,
        endsWith('/webhooks/w1'),
      );
      expect(find.text('#alerts'), findsNothing);
    });
  });
}
