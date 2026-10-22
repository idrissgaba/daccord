import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:bonfire/features/voice/views/voice_moderation_menu.dart';
import 'package:bonfire/features/voice/views/voice_participants.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A [VoiceSession] stand-in that records connects and mic toggles.
class _FakeSession extends VoiceSession {
  int connects = 0;
  bool? connectedMuted;
  final micToggles = <bool>[];

  @override
  String? get micError => null;

  @override
  String? get lastError => null;

  @override
  Future<void> connect(
    String url,
    String token, {
    bool selfMute = false,
    bool selfDeaf = false,
    String? audioInputDeviceId,
    String? audioOutputDeviceId,
    int outputVolume = 100,
    int inputVolume = 100,
    bool relayOnly = false,
    Map<String, int>? userVolumes,
    VoiceAudioOptions? audio,
  }) async {
    connects++;
    connectedMuted = selfMute;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<String?> setMicEnabled(bool enabled) async {
    micToggles.add(enabled);
    return null;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeAccordAuth extends AccordAuth {
  _FakeAccordAuth(this._client, {this.initial = const AccordAuthLoggedOut()});
  final AccordClient _client;
  final AccordAuthState initial;

  @override
  AccordAuthState build() => initial;

  @override
  AccordClient? clientForKey(String key) => _client;
}

class _ActiveConnections extends ConnectionsController {
  _ActiveConnections(this.key);
  final String key;
  @override
  ConnectionsState build() => ConnectionsState(activeKey: key);
}

class _FixedSettingsController extends SettingsController {
  @override
  AccordSettings build() => AccordSettings();
}

/// Sits unmuted in channel c1 of space s1.
class _InCallVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection(
    channelId: 'c1',
    spaceId: 's1',
    serverKey: 'server-key',
  );
}

/// A REST stand-in: answers the voice join with [joinStatus]/[joinBody] and
/// everything else with an empty list, recording each request.
({AccordClient client, List<http.Request> requests}) _client({
  int joinStatus = 200,
  Map<String, dynamic>? joinBody,
}) {
  final requests = <http.Request>[];
  final responder = MockClient((request) async {
    requests.add(request);
    final isJoin =
        request.method == 'POST' && request.url.path.endsWith('/voice/join');
    if (isJoin) {
      return http.Response(
        jsonEncode(
          joinBody ??
              {
                'space_id': 's1',
                'channel_id': 'c1',
                'backend': 'livekit',
                'livekit_url': 'wss://livekit.example',
                'token': 'lk-token',
              },
        ),
        joinStatus,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      '[]',
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: 'https://accord.example',
    gatewayUrl: 'wss://accord.example/ws',
    httpClient: responder,
  );
  addTearDown(client.dispose);
  return (client: client, requests: requests);
}

({
  ProviderContainer container,
  _FakeSession session,
  List<http.Request> requests,
})
_harness({
  VoiceController Function()? voice,
  int joinStatus = 200,
  Map<String, dynamic>? joinBody,
}) {
  final rest = _client(joinStatus: joinStatus, joinBody: joinBody);
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWith(() => _FakeAccordAuth(rest.client)),
      connectionsControllerProvider.overrideWith(
        () => _ActiveConnections('server-key'),
      ),
      settingsControllerProvider.overrideWith(_FixedSettingsController.new),
      if (voice != null) voiceControllerProvider.overrideWith(voice),
    ],
  );
  addTearDown(container.dispose);
  final session = _FakeSession();
  container.read(voiceControllerProvider.notifier).debugSession = session;
  return (container: container, session: session, requests: rest.requests);
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

AccordVoiceState _vs({
  String userId = 'u-self',
  String channelId = 'c1',
  bool mute = false,
  bool deaf = false,
  bool suppress = false,
  bool selfMute = false,
}) => AccordVoiceState(
  userId: userId,
  spaceId: 's1',
  channelId: channelId,
  mute: mute,
  deaf: deaf,
  suppress: suppress,
  selfMute: selfMute,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => soundManager.voiceSessionActive = false);

  group('voice moderation logic', () {
    test('the strongest server restriction explains itself', () {
      expect(
        voiceSpeakBlockedReason(
          serverMute: true,
          serverDeaf: true,
          suppressed: true,
        ),
        'A moderator has deafened you.',
      );
      expect(
        voiceSpeakBlockedReason(
          serverMute: true,
          serverDeaf: false,
          suppressed: true,
        ),
        'A moderator has muted you.',
      );
      expect(
        voiceSpeakBlockedReason(
          serverMute: false,
          serverDeaf: false,
          suppressed: true,
        ),
        "You don't have permission to speak in this channel.",
      );
      expect(
        voiceSpeakBlockedReason(
          serverMute: false,
          serverDeaf: false,
          suppressed: false,
        ),
        isNull,
      );
    });

    test('join errors read as sentences', () {
      expect(
        voiceJoinErrorMessage('channel_full'),
        'This voice channel is full.',
      );
      expect(voiceJoinErrorMessage(null), 'Failed to join voice channel');
      expect(
        voiceJoinErrorMessage('missing permission: connect'),
        'missing permission: connect',
      );
    });

    test('occupancy shows the cap when there is one', () {
      expect(voiceOccupancyLabel(0, null), isNull);
      expect(voiceOccupancyLabel(3, null), '3');
      expect(voiceOccupancyLabel(0, 5), '0/5');
      expect(voiceOccupancyLabel(2, '10'), '2/10');
      expect(voiceOccupancyLabel(2, 0), '2');
      expect(voiceUserLimit(4.0), 4);
      expect(voiceUserLimit('x'), isNull);
    });

    test('a move only applies where it started', () {
      expect(
        isMoveForUs(
          currentChannelId: 'a',
          fromChannelId: 'a',
          toChannelId: 'b',
        ),
        isTrue,
      );
      expect(
        isMoveForUs(
          currentChannelId: 'a',
          fromChannelId: null,
          toChannelId: 'b',
        ),
        isTrue,
      );
      expect(
        isMoveForUs(
          currentChannelId: 'c',
          fromChannelId: 'a',
          toChannelId: 'b',
        ),
        isFalse,
      );
      expect(
        isMoveForUs(
          currentChannelId: 'b',
          fromChannelId: 'a',
          toChannelId: 'b',
        ),
        isFalse,
      );
      expect(
        isMoveForUs(
          currentChannelId: null,
          fromChannelId: 'a',
          toChannelId: 'b',
        ),
        isFalse,
      );
    });

    test('rights come from the voice moderation permissions', () {
      final none = VoiceModerationRights.from({'speak'});
      expect(none.any, isFalse);
      final mod = VoiceModerationRights.from({
        AccordPermission.muteMembers,
        AccordPermission.moveMembers,
      });
      expect((mod.mute, mod.deafen, mod.move), (true, false, true));
      final admin = VoiceModerationRights.from({
        AccordPermission.administrator,
      });
      expect((admin.mute, admin.deafen, admin.move), (true, true, true));
    });

    test('move targets are the other voice channels', () {
      final channels = [
        AccordChannel(id: 'c1', type: 'voice'),
        AccordChannel(id: 't1', type: 'text'),
        AccordChannel(id: 'c2', type: 'voice'),
      ];
      expect(voiceMoveTargets(channels, 'c1').map((c) => c.id), ['c2']);
    });

    test('a drag drops only on another channel of the same space', () {
      const drag = VoiceMoveDrag(
        serverKey: 'k',
        spaceId: 's1',
        fromChannelId: 'c1',
        userId: 'u',
        name: 'U',
      );
      expect(drag.canDropOn('s1', 'c2'), isTrue);
      expect(drag.canDropOn('s1', 'c1'), isFalse);
      expect(drag.canDropOn('s2', 'c2'), isFalse);
    });

    test('a move event parses its origin', () {
      final info = AccordVoiceServerUpdate.fromJson({
        'channel_id': 'c2',
        'from_channel_id': 'c1',
        'moved': true,
        'url': 'wss://lk',
        'token': 't',
        'voice_state': {'user_id': 'u', 'channel_id': 'c2', 'mute': true},
      });
      expect(info.moved, isTrue);
      expect(info.fromChannelId, 'c1');
      expect(info.voiceState?.mute, isTrue);
      expect(
        AccordVoiceServerUpdate.fromJson({'channel_id': 'c'}).moved,
        isFalse,
      );
    });
  });

  group('voice controller', () {
    test(
      'a server-muted join connects without the mic and refuses to unmute',
      () async {
        final h = _harness(
          joinBody: {
            'space_id': 's1',
            'channel_id': 'c1',
            'backend': 'livekit',
            'livekit_url': 'wss://livekit.example',
            'token': 'lk-token',
            'voice_state': {
              'user_id': 'u-self',
              'channel_id': 'c1',
              'mute': true,
            },
          },
        );
        final controller = h.container.read(voiceControllerProvider.notifier);
        await controller.join('c1', 's1');
        final state = h.container.read(voiceControllerProvider);
        expect(state.serverMute, isTrue);
        expect(state.selfMute, isFalse);
        expect(h.session.connectedMuted, isTrue);

        controller.setMute(true);
        controller.setMute(false);
        await pump();
        expect(h.session.micToggles, [false]);
        expect(
          h.container.read(voiceControllerProvider).error,
          'A moderator has muted you.',
        );
      },
    );

    test('a full channel says so', () async {
      final h = _harness(
        joinStatus: 403,
        joinBody: {
          'error': {'code': 'forbidden', 'message': 'channel_full'},
        },
      );
      await h.container.read(voiceControllerProvider.notifier).join('c1', 's1');
      final state = h.container.read(voiceControllerProvider);
      expect(state.isConnected, isFalse);
      expect(state.error, 'This voice channel is full.');
    });

    test('server flags mid-call turn the mic off, then back on', () async {
      final h = _harness(voice: _InCallVoiceController.new);
      final controller = h.container.read(voiceControllerProvider.notifier);

      controller.applyServerFlags(_vs(mute: true));
      await pump();
      expect(h.session.micToggles, [false]);
      expect(h.container.read(voiceControllerProvider).canSpeak, isFalse);

      // A state for another channel (a stale echo) changes nothing.
      controller.applyServerFlags(_vs(channelId: 'c9'));
      expect(h.container.read(voiceControllerProvider).serverMute, isTrue);

      controller.applyServerFlags(_vs());
      await pump();
      expect(h.session.micToggles, [false, true]);
      expect(h.container.read(voiceControllerProvider).canSpeak, isTrue);
    });

    test('a move reconnects to the new room without leaving voice', () async {
      final h = _harness(voice: _InCallVoiceController.new);
      final controller = h.container.read(voiceControllerProvider.notifier);
      controller.handleServerUpdate(
        AccordVoiceServerUpdate.fromJson({
          'space_id': 's1',
          'channel_id': 'c2',
          'from_channel_id': 'c1',
          'moved': true,
          'url': 'wss://livekit.example',
          'token': 'moved-token',
          'voice_state': {
            'user_id': 'u-self',
            'channel_id': 'c2',
            'suppress': true,
          },
        }),
        serverKey: 'server-key',
      );
      await pump();
      await pump();
      final state = h.container.read(voiceControllerProvider);
      expect(state.channelId, 'c2');
      expect(state.suppressed, isTrue);
      expect(h.session.connects, 1);
      expect(h.session.connectedMuted, isTrue);
      expect(
        h.requests.where((r) => r.url.path.endsWith('/voice/leave')),
        isEmpty,
      );
    });

    test(
      'a move that started elsewhere, or on another server, is ignored',
      () async {
        final h = _harness(voice: _InCallVoiceController.new);
        final controller = h.container.read(voiceControllerProvider.notifier);
        final move = AccordVoiceServerUpdate.fromJson({
          'channel_id': 'c2',
          'from_channel_id': 'c7',
          'moved': true,
          'url': 'wss://livekit.example',
          'token': 't',
        });
        controller.handleServerUpdate(move, serverKey: 'server-key');
        await pump();
        move.fromChannelId = 'c1';
        controller.handleServerUpdate(move, serverKey: 'other-server');
        await pump();
        expect(h.container.read(voiceControllerProvider).channelId, 'c1');
        expect(h.session.connects, 0);
      },
    );
  });

  group('voice moderation UI', () {
    Widget host({
      required Map<String, AccordVoiceState> states,
      List<http.Request>? requests,
      String ownerId = 'u-self',
    }) {
      final server = AccordServer.fromBaseUrl('https://accord.example.test');
      final client = AccordClient(
        token: 'test-token',
        tokenType: 'Bearer',
        baseUrl: server.baseUrl,
        gatewayUrl: server.gatewayUrl,
        cdnUrl: server.cdnUrl,
        httpClient: MockClient((request) async {
          requests?.add(request);
          return http.Response(
            jsonEncode({'user_id': 'u-other', 'space_id': 's1'}),
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
          token: 'test-token',
          userId: 'u-self',
          username: 'self',
        ),
      );
      return ProviderScope(
        overrides: [
          accordAuthProvider.overrideWith(
            () => _FakeAccordAuth(client, initial: loggedIn),
          ),
          connectionsControllerProvider.overrideWith(
            () => _ActiveConnections(''),
          ),
          spacesControllerProvider.overrideWith(
            () => _Spaces([AccordSpace(id: 's1', ownerId: ownerId)]),
          ),
          accordMembersControllerProvider('', 's1').overrideWith(_Members.new),
          accordChannelsControllerProvider('', 's1').overrideWith(
            () => _Channels([
              AccordChannel(id: 'c1', type: 'voice', name: 'Lounge'),
              AccordChannel(id: 'c2', type: 'voice', name: 'Games'),
            ]),
          ),
          accordUsersControllerProvider('').overrideWith(_Users.new),
          voiceControllerProvider.overrideWith(_IdleVoice.new),
          voiceStatesControllerProvider(
            '',
          ).overrideWith(() => _States({'c1': states})),
          activePresencesProvider.overrideWithValue(const PresenceMap()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: const Scaffold(
            body: Column(
              children: [
                VoiceParticipantList(channelId: 'c1', spaceId: 's1'),
                VoiceModerationPanel(
                  serverKey: '',
                  spaceId: 's1',
                  channelId: 'c1',
                  userId: 'u-other',
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('server flags show as icons on the participant row', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          states: {
            'u-other': _vs(userId: 'u-other', mute: true),
            'u-third': _vs(userId: 'u-third', deaf: true),
          },
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('voice-participant-server-mute')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('voice-participant-server-deaf')),
        findsOneWidget,
      );
    });

    testWidgets('a moderator mutes, moves and disconnects from the panel', (
      tester,
    ) async {
      final requests = <http.Request>[];
      await tester.pumpWidget(
        host(
          states: {'u-other': _vs(userId: 'u-other')},
          requests: requests,
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('voice-mod-mute')));
      await tester.pumpAndSettle();
      expect(requests.last.method, 'PATCH');
      expect(requests.last.url.path, endsWith('/spaces/s1/members/u-other'));
      expect(jsonDecode(requests.last.body), {'mute': true});

      await tester.tap(find.byKey(const Key('voice-mod-move')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Games').last);
      await tester.pumpAndSettle();
      expect(jsonDecode(requests.last.body), {'channel_id': 'c2'});

      await tester.tap(find.byKey(const Key('voice-mod-disconnect')));
      await tester.pumpAndSettle();
      expect(jsonDecode(requests.last.body), {'channel_id': null});
    });

    testWidgets('members without the rights see no moderation actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          states: {'u-other': _vs(userId: 'u-other')},
          ownerId: 'u-boss',
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('voice-mod-mute')), findsNothing);
      expect(find.byKey(const Key('voice-mod-disconnect')), findsNothing);
    });
  });
}

class _Spaces extends SpacesController {
  _Spaces(this.spaces);
  final List<AccordSpace> spaces;
  @override
  List<AccordSpace>? build() => spaces;
}

class _Members extends AccordMembersController {
  @override
  Map<String, AccordMember>? build(String serverKey, String spaceId) =>
      const {};
}

class _Channels extends AccordChannelsController {
  _Channels(this.channels);
  final List<AccordChannel> channels;
  @override
  List<AccordChannel>? build(String serverKey, String spaceId) => channels;
}

class _Users extends AccordUsersController {
  @override
  Map<String, AccordUser> build(String serverKey) => const {};
  @override
  void ensure(String userId) {}
}

class _IdleVoice extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection();
}

class _States extends VoiceStatesController {
  _States(this.states);
  final Map<String, Map<String, AccordVoiceState>> states;
  @override
  Map<String, Map<String, AccordVoiceState>> build(String serverKey) => states;
}
