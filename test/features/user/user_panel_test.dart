import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/user/views/user_panel.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Voice extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection();
  @override
  void toggleMute() => state = state.copyWith(selfMute: !state.selfMute);
}

void main() {
  testWidgets('the user panel shows who you are and mutes', (tester) async {
    var settings = 0;
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    final client = AccordClient(token: 't', baseUrl: server.baseUrl);
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
                userId: 'u1',
                username: 'alice',
              ),
            ),
          ),
          voiceControllerProvider.overrideWith(_Voice.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: UserPanel(
              onOpenSettings: () => settings++,
              onSwitchAccount: () {},
              onLogout: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.mic), findsOneWidget);

    await tester.tap(find.byKey(const Key('user-panel-mute')));
    await tester.pump();
    expect(find.byIcon(Icons.mic_off), findsOneWidget);

    await tester.tap(find.byKey(const Key('user-panel-settings')));
    expect(settings, 1);
  });
}
