import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _channelId = 'c1';
const _selfId = 'u1';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

/// A logged-in [MessagePane] backed by [MockClient], plus the request log and
/// the live message controller so tests can inject a "new message arrived"
/// gateway event mid-await.
class _Harness {
  /// [failDeleteOf] makes the DELETE request for that message id come back
  /// as a server error instead of succeeding, to exercise the failure path.
  _Harness(List<Map<String, String>> seed, {String? failDeleteOf}) {
    final responder = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' &&
          request.url.path.endsWith('/channels/$_channelId/messages')) {
        return http.Response(
          jsonEncode(seed.reversed.toList()), // REST returns newest-first
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'DELETE' &&
          failDeleteOf != null &&
          request.url.path.endsWith('/messages/$failDeleteOf')) {
        return http.Response('', 500);
      }
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    client = AccordClient(
      token: 'test-token',
      tokenType: 'Bearer',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
      httpClient: responder,
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(
            client: client,
            session: AccordSession(
              server: server,
              token: 'test-token',
              userId: _selfId,
              username: 'self',
            ),
          ),
        ),
        // Keeps the row/composer off the (unopened) `accord-settings` Hive box.
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      ],
    );
  }

  final List<String> requests = [];
  late final AccordClient client;
  late final ProviderContainer container;

  AccordMessagesController get messages =>
      container.read(accordMessagesControllerProvider('', _channelId).notifier);

  /// Requests against [messageId]'s own sub-resources — i.e. everything except
  /// the channel-level message list. The suffix after the id is kept so the
  /// verb/endpoint can be asserted too.
  List<String> requestsFor(String messageId) => [
    for (final r in requests)
      if (r.contains('/messages/$messageId')) r,
  ];

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      // spaceId: null keeps the pane off the member/role/emoji caches; the row
      // behaviour under test doesn't depend on them.
      home: const Scaffold(
        body: MessagePane(channel: null, channelId: _channelId, spaceId: null),
      ),
    ),
  );

  /// Only the HTTP client is torn down here: the [ProviderContainer] has to
  /// outlive the widget tree, which is finalized after the test's tear-downs
  /// run (the composer saves its draft through the settings provider on
  /// dispose).
  void dispose() => client.dispose();
}

Map<String, String> _msgJson(String id, String content) => {
  'id': id,
  'channel_id': _channelId,
  'author_id': _selfId,
  'content': content,
  'timestamp': '2026-01-01T10:00:00Z',
};

/// Message bodies render as markdown, so they're [RichText], not [Text].
Finder _body(String text) => find.text(text, findRichText: true);

/// Pumps enough frames for a mocked request or a route transition to complete.
/// `pumpAndSettle` can't be used: the pane shows an indeterminate spinner while
/// the first page loads, which never settles.
Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('a text selection survives the pointer leaving the row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    final harness = _Harness([_msgJson('m1', 'select this text please')]);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    await _tick(tester);

    // Drag-select the start of the message with the mouse.
    final text = _body('select this text please');
    final left = tester.getTopLeft(text) + const Offset(1, 8);
    final mouse = await tester.startGesture(
      left,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await mouse.moveTo(left + const Offset(60, 0));
    await tester.pump();
    await mouse.up();
    await tester.pump();

    await mouse.removePointer();

    // Right-click the selection: the message's own menu opens, with Copy
    // selection on top, as in other chat apps.
    final right = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await right.addPointer(location: left + const Offset(20, 0));
    await right.down(left + const Offset(20, 0));
    await right.up();
    await _tick(tester, frames: 4);
    expect(find.text('Copy selection'), findsOneWidget);
    expect(find.text('Reply'), findsWidgets);

    // Moving the pointer onto the menu leaves it open.
    await right.moveTo(tester.getCenter(find.text('Copy selection')));
    await _tick(tester, frames: 4);
    expect(find.text('Copy selection'), findsOneWidget);

    await tester.tap(find.text('Copy selection'));
    await _tick(tester, frames: 4);
    expect(copied, startsWith('sel'));
    await right.removePointer();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
