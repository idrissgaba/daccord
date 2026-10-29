import 'package:accordkit/accordkit.dart' show AccordVoiceState;
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A session where `u2` has a screen share published, which we may or may not
/// be receiving. No LiveKit room: the publication is simulated.
class _StreamingSession extends VoiceSession {
  final watched = <String>{};
  final calls = <(String, bool)>[];

  @override
  bool remoteIsStreaming(String userId) => userId == 'u2';

  @override
  bool isWatchingStream(String userId) => watched.contains(userId);

  @override
  Future<void> setWatchingStream(String userId, bool watch) async {
    calls.add((userId, watch));
    if (watch) {
      watched.add(userId);
    } else {
      watched.remove(userId);
    }
    onTracksChanged?.call();
  }
}

class _ConnectedVoiceController extends VoiceController {
  _ConnectedVoiceController(this._session);

  final _StreamingSession _session;

  @override
  VoiceConnection build() {
    debugSession = _session;
    _session.onTracksChanged = () =>
        state = state.copyWith(tick: state.tick + 1);
    return const VoiceConnection(channelId: 'c1', spaceId: 's1');
  }
}

class _FakeVoiceStates extends VoiceStatesController {
  @override
  Map<String, Map<String, AccordVoiceState>> build(String serverKey) => {
    'c1': {
      'u1': AccordVoiceState(userId: 'u1', channelId: 'c1'),
      'u2': AccordVoiceState(userId: 'u2', channelId: 'c1', selfStream: true),
    },
  };
}

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

Widget _host(_ConnectedVoiceController voice) => ProviderScope(
  overrides: [
    accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
    settingsControllerProvider.overrideWith(_FakeSettingsController.new),
    voiceControllerProvider.overrideWith(() => voice),
    voiceStatesControllerProvider('').overrideWith(_FakeVoiceStates.new),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: const Scaffold(
      body: VoiceChannelView(
        channelId: 'c1',
        spaceId: 's1',
        channelName: 'general-voice',
      ),
    ),
  ),
);

void main() {
  testWidgets("a peer's stream is a live card until you choose to watch it", (
    tester,
  ) async {
    final session = _StreamingSession();
    final voice = _ConnectedVoiceController(session);
    await tester.pumpWidget(_host(voice));
    await tester.pump();

    // Nothing is received by default: the tile only says they are live.
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.byKey(const Key('watch-stream-u2')), findsOneWidget);
    expect(find.byKey(const Key('stop-watching-u2')), findsNothing);
    expect(session.calls, isEmpty);

    await tester.tap(find.byKey(const Key('watch-stream-u2')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(session.calls, [('u2', true)]);
    expect(find.text('LIVE'), findsNothing);
    expect(find.byKey(const Key('stop-watching-u2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stop-watching-u2')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(session.calls, [('u2', true), ('u2', false)]);
    expect(find.byKey(const Key('watch-stream-u2')), findsOneWidget);
  });
}
