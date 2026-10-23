import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/views/profile_extras.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
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
}

void main() {
  test('profile extras parse, and streamer mode persists', () {
    final extras = AccordProfileExtras.fromJson({
      'user_id': 'u',
      'pronouns': 'they/them',
      'theme_primary': 0x5865F2,
      'theme_accent': null,
      'note': 'Plays bass',
    });
    expect(extras.hasTheme, isTrue);
    expect(extras.note, 'Plays bass');
    expect(profileColor(0x5865F2), const Color(0xFF5865F2));

    const settings = AccordSettings(streamerMode: true);
    expect(settings.toJson()['streamerMode'], isTrue);
    expect(AccordSettings.fromJson(settings.toJson()).streamerMode, isTrue);
    expect(AccordSettings.fromJson(const {}).streamerMode, isFalse);
  });

  group('profile card', () {
    late List<http.Request> requests;

    Widget host({bool streamer = false, bool isSelf = false}) {
      requests = [];
      final server = AccordServer.fromBaseUrl('https://chat.example');
      final client = AccordClient(
        token: 't',
        baseUrl: server.baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          final body = request.method == 'GET'
              ? {
                  'data': {
                    'user_id': 'u2',
                    'pronouns': 'she/her',
                    'theme_primary': 0xEB459E,
                    'theme_accent': 0x5865F2,
                    'note': 'Old friend',
                  },
                }
              : {'data': {}};
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      return ProviderScope(
        overrides: [
          accordAuthProvider.overrideWithValue(
            AccordAuthLoggedIn(
              client: client,
              session: AccordSession(
                server: server,
                token: 't',
                userId: 'u1',
                username: 'me',
              ),
            ),
          ),
          settingsControllerProvider.overrideWith(
            () => _Settings(AccordSettings(streamerMode: streamer)),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: Column(
              children: [
                const ProfileThemeBand(serverKey: '', userId: 'u2'),
                ProfileExtrasSection(
                  serverKey: '',
                  userId: 'u2',
                  isSelf: isSelf,
                  bio: 'Loves synths',
                ),
                const StreamerModeBar(),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('shows pronouns, about me, theme and the private note', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('she/her'), findsOneWidget);
      expect(find.text('Loves synths'), findsOneWidget);
      expect(find.byKey(const Key('profile-theme-band')), findsOneWidget);
      expect(find.text('Old friend'), findsOneWidget);
      expect(find.byKey(const Key('streamer-mode-bar')), findsNothing);

      await tester.enterText(find.byKey(const Key('profile-note')), 'Bassist');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      final put = requests.lastWhere((r) => r.method == 'PUT');
      expect(put.url.path, endsWith('/users/@me/notes/u2'));
      expect(jsonDecode(put.body), {'note': 'Bassist'});
    });

    testWidgets('streamer mode hides the note and says it is on', (
      tester,
    ) async {
      await tester.pumpWidget(host(streamer: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-note')), findsNothing);
      expect(find.text('she/her'), findsOneWidget);
      expect(find.byKey(const Key('streamer-mode-bar')), findsOneWidget);
    });

    testWidgets('no note on our own card', (tester) async {
      await tester.pumpWidget(host(isSelf: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-note')), findsNothing);
    });
  });
}
