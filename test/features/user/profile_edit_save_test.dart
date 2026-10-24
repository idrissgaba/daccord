import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/member/views/profile_extras.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/user/views/accord_profile_edit.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  _Auth(this.fixtureClient, this.account);
  final AccordClient fixtureClient;
  final AccordSession account;
  @override
  AccordAuthState build() =>
      AccordAuthLoggedIn(client: fixtureClient, session: account);
  @override
  AccordClient? clientForKey(String key) =>
      key == account.key ? fixtureClient : null;
}

class _Connections extends ConnectionsController {
  _Connections(this.account);
  final AccordSession account;
  @override
  ConnectionsState build() => ConnectionsState(
    activeKey: account.key,
    connections: [
      AccordConnection(session: account, status: ConnectionStatus.ready),
    ],
  );
}

void main() {
  testWidgets('Save stays reachable and saves the theme on a short window', (
    tester,
  ) async {
    // Short enough that the fields can't all fit the dialog.
    tester.view.physicalSize = const Size(900, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final requests = <http.Request>[];
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    final account = AccordSession(
      server: server,
      token: 't',
      userId: 'u1',
      username: 'alice',
    );
    final client = AccordClient(
      token: 't',
      baseUrl: server.baseUrl,
      httpClient: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        final Object data = path.endsWith('/profile')
            ? {'user_id': 'u1', 'pronouns': 'she/her'}
            : {'id': 'u1', 'username': 'alice'};
        return http.Response(
          jsonEncode({'data': data}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accordAuthProvider.overrideWith(() => _Auth(client, account)),
          connectionsControllerProvider.overrideWith(
            () => _Connections(account),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAccordProfileEdit(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final swatch = find
        .byWidgetPredicate(
          (w) =>
              w is CircleAvatar &&
              w.backgroundColor == profileColor(profileThemePalette.first),
        )
        .first;
    await tester.ensureVisible(swatch);
    await tester.pumpAndSettle();
    await tester.tap(swatch);
    await tester.pump();
    final save = find.text('Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final patch = requests.lastWhere(
      (r) => r.method == 'PATCH' && r.url.path.endsWith('/users/@me/profile'),
    );
    expect(jsonDecode(patch.body)['theme_primary'], profileThemePalette.first);
  });
}
