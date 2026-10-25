import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('a profile can send a friend request', (tester) async {
    final requests = <http.Request>[];
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    final client = AccordClient(
      token: 't',
      baseUrl: server.baseUrl,
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'data': request.method == 'GET' ? [] : null}),
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
                userId: 'me',
                username: 'me',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: FriendActionButton(
              user: AccordUser(id: 'u2', username: 'bob'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add friend'), findsOneWidget);

    await tester.tap(find.text('Add friend'));
    await tester.pumpAndSettle();
    final put = requests.firstWhere((r) => r.method == 'PUT');
    expect(put.url.path, endsWith('/users/@me/relationships/u2'));
    expect(jsonDecode(put.body), {'type': 1});
  });
}
