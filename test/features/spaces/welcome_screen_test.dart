import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/welcome_screen.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Settings extends SettingsController {
  _Settings(this.initial);
  final AccordSettings initial;
  @override
  AccordSettings build() => initial;
  @override
  void markWelcomeSeen(String serverKey, String spaceId) {
    state = state.copyWith(
      seenWelcomeScreens: [...state.seenWelcomeScreens, '$serverKey/$spaceId'],
    );
  }
}

class _Channels extends AccordChannelsController {
  @override
  List<AccordChannel>? build(String serverKey, String spaceId) => [
    AccordChannel(id: 'c1', type: 'text', name: 'general'),
  ];
}

void main() {
  test('welcome screens round-trip and are remembered once seen', () {
    final screen = AccordWelcomeScreen.fromJson({
      'enabled': true,
      'description': 'Hi!',
      'channels': [
        {'channel_id': 'c1', 'description': 'Say hello', 'emoji': '👋'},
      ],
    });
    expect(screen.channels.single.emoji, '👋');
    expect(screen.toJson()['channels'][0]['channel_id'], 'c1');

    const settings = AccordSettings();
    expect(settings.isWelcomeSeen('k', 's'), isFalse);
    final json = settings.copyWith(seenWelcomeScreens: ['x']).toJson();
    expect(AccordSettings.fromJson(json).seenWelcomeScreens, ['x']);
  });

  testWidgets('the gate shows the screen once and opens a channel', (
    tester,
  ) async {
    var gets = 0;
    final server = AccordServer.fromBaseUrl('https://chat.example');
    final client = AccordClient(
      token: 't',
      baseUrl: server.baseUrl,
      httpClient: MockClient((request) async {
        gets++;
        return http.Response(
          jsonEncode({
            'data': {
              'enabled': true,
              'description': 'Make yourself at home',
              'channels': [
                {'channel_id': 'c1', 'description': 'Say hello', 'emoji': '👋'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    String? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accordAuthProvider.overrideWithValue(
            AccordAuthLoggedIn(
              client: client,
              session: AccordSession(
                server: server,
                token: 't',
                userId: 'u',
                username: 'u',
              ),
            ),
          ),
          settingsControllerProvider.overrideWith(
            () => _Settings(const AccordSettings()),
          ),
          spacesControllerProvider.overrideWithValue([
            AccordSpace(id: 's1', name: 'Friends'),
          ]),
          accordChannelsControllerProvider(
            '',
            's1',
          ).overrideWith(_Channels.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: WelcomeScreenGate(
              spaceId: 's1',
              onOpenChannel: (id) => opened = id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Friends!'), findsOneWidget);
    expect(find.text('Make yourself at home'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('welcome-channel-c1')));
    await tester.pumpAndSettle();
    expect(opened, 'c1');
    expect(gets, 1);
  });
}
