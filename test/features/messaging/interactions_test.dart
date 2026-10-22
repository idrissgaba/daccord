import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/messaging/controllers/app_commands.dart';
import 'package:bonfire/features/messaging/utils/interaction_logic.dart';
import 'package:bonfire/features/messaging/views/command_picker.dart';
import 'package:bonfire/features/messaging/views/message_components.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AccordCommand _play() => AccordCommand.fromJson({
  'id': 'cmd-play',
  'application_id': 'app',
  'name': 'play',
  'description': 'Play a song',
  'options': [
    {
      'name': 'query',
      'description': 'Song or URL',
      'type': 'string',
      'required': true,
    },
    {
      'name': 'volume',
      'description': 'Volume',
      'type': 'integer',
      'min_value': 0,
      'max_value': 200,
    },
  ],
  'application': {'id': 'app', 'name': 'Music', 'bot_user_id': 'bot'},
});

AccordCommand _skip() => AccordCommand.fromJson({
  'id': 'cmd-skip',
  'application_id': 'app',
  'name': 'skip',
  'description': 'Skip the song',
  'application': {'id': 'app', 'name': 'Music', 'bot_user_id': 'bot'},
});

AccordCommand _mode() => AccordCommand.fromJson({
  'id': 'cmd-loop',
  'application_id': 'app',
  'name': 'loop',
  'description': 'Loop mode',
  'options': [
    {
      'name': 'mode',
      'description': 'Mode',
      'type': 'string',
      'required': true,
      'choices': [
        {'name': 'Off', 'value': 'off'},
        {'name': 'Song', 'value': 'song'},
      ],
    },
  ],
});

class _Commands extends SpaceCommandsController {
  _Commands(this.commands);
  final List<AccordCommand> commands;
  @override
  List<AccordCommand>? build(String serverKey, String spaceId) => commands;
}

class _FakeSettings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
  @override
  void setDraft(String serverKey, String channelId, String text) {}
}

void main() {
  group('slash command logic', () {
    test('a slash query is the name being typed', () {
      expect(slashQuery('/'), '');
      expect(slashQuery('/Pl'), 'pl');
      expect(slashQuery('/play daft'), isNull);
      expect(slashQuery('hello /play'), isNull);
    });

    test('matches put prefixes first', () {
      final commands = [_skip(), _play(), _mode()];
      expect(matchCommands(commands, '').map((c) => c.name), [
        'skip',
        'play',
        'loop',
      ]);
      expect(matchCommands(commands, 'p').map((c) => c.name), ['play']);
      expect(matchCommands(commands, 'oo').map((c) => c.name), ['loop']);
      expect(matchCommands(commands, 'o'), isEmpty);
    });

    test('a typed command runs when the text fills it', () {
      final commands = [_play(), _skip(), _mode()];
      final play = parseQuickCommand('/play daft punk', commands)!;
      expect(play.command.name, 'play');
      expect(play.options, [
        {'name': 'query', 'value': 'daft punk'},
      ]);
      expect(parseQuickCommand('/skip', commands)!.options, isEmpty);
      // Needs the form: a required option missing, or fixed choices.
      expect(parseQuickCommand('/play', commands), isNull);
      expect(parseQuickCommand('/loop song', commands), isNull);
      expect(parseQuickCommand('/nope x', commands), isNull);
      expect(parseQuickCommand('play x', commands), isNull);
    });

    test('option values are checked like the server does', () {
      final volume = _play().options[1];
      expect(optionValue(volume, '80').value, 80);
      expect(optionValue(volume, '300').error, contains('between 0 and 200'));
      expect(optionValue(volume, 'loud').error, contains('whole number'));
      expect(optionValue(volume, '').value, isNull);
      expect(optionValue(volume, '').error, isNull);
      final query = _play().options.first;
      expect(optionValue(query, '  ').error, 'query is required');

      final collected = collectOptions(_play(), {'query': ' x ', 'volume': ''});
      expect(collected.error, isNull);
      expect(collected.options, [
        {'name': 'query', 'value': 'x'},
      ]);
      expect(collectOptions(_mode(), {'mode': 'loud'}).error, isNotNull);
    });

    test('components parse, skipping what is malformed', () {
      final rows = parseComponents([
        {
          'type': 'action_row',
          'components': [
            {
              'type': 'button',
              'style': 'primary',
              'label': 'Pause',
              'custom_id': 'pause',
            },
            {'type': 2, 'style': 5, 'label': 'Source', 'url': 'https://x.test'},
            {'type': 2, 'style': 5, 'label': 'No url'},
            {
              'type': 'button',
              'style': 'danger',
              'label': 'Stop',
              'custom_id': 'stop',
              'disabled': true,
              'emoji': {'name': '⏹'},
            },
          ],
        },
        {
          'type': 1,
          'components': [
            {
              'type': 'select',
              'custom_id': 'pick',
              'options': [
                {'label': 'One', 'value': '1'},
                {'label': 'Two', 'value': '2', 'default': true},
              ],
            },
          ],
        },
        'junk',
      ]);
      expect(rows, hasLength(2));
      final buttons = rows.first.cast<ComponentButton>();
      expect(buttons.map((b) => b.label), ['Pause', 'Source', 'Stop']);
      expect(buttons[1].style, ComponentButtonStyle.link);
      expect(buttons[2].disabled, isTrue);
      expect(buttons[2].emoji, '⏹');
      final select = rows.last.single as ComponentSelect;
      expect(select.options.last.isDefault, isTrue);
    });

    test('message flags mark ephemeral and loading answers', () {
      final message = AccordMessage.fromJson({
        'id': 'm',
        'channel_id': 'c',
        'author_id': 'bot',
        'content': '',
        'flags': 64 | 128,
        'interaction': {
          'id': 'i',
          'type': 'application_command',
          'name': 'play',
          'user_id': 'u',
        },
      });
      expect(isEphemeralMessage(message), isTrue);
      expect(isLoadingMessage(message), isTrue);
      expect(message.interaction?.name, 'play');
      expect(message.toJson()['interaction']['user_id'], 'u');
    });
  });

  group('interaction tracker', () {
    testWidgets('success clears, silence fails then clears', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final tracker = container.read(interactionTrackerProvider.notifier);
      tracker.started(
        const PendingInteraction(id: 'a', channelId: 'c', commandName: 'play'),
      );
      tracker.started(
        const PendingInteraction(id: 'b', channelId: 'c', commandName: 'skip'),
      );
      tracker.succeeded('a');
      expect(container.read(interactionTrackerProvider).keys, ['b']);
      await tester.pump(interactionTimeout + const Duration(milliseconds: 1));
      expect(container.read(interactionTrackerProvider)['b']!.failed, isTrue);
      await tester.pump(const Duration(seconds: 6));
      expect(container.read(interactionTrackerProvider), isEmpty);
    });

    test('a success that beats the request is remembered', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final tracker = container.read(interactionTrackerProvider.notifier);
      tracker.succeeded('early');
      tracker.started(const PendingInteraction(id: 'early', channelId: 'c'));
      expect(container.read(interactionTrackerProvider), isEmpty);
    });
  });

  group('widgets', () {
    Widget wrap(Widget child, {List<Override> overrides = const []}) =>
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: buildAppTheme(AppThemePreset.dark),
            home: Scaffold(body: child),
          ),
        );

    testWidgets('the popup lists matching commands', (tester) async {
      AccordCommand? picked;
      await tester.pumpWidget(
        wrap(
          CommandPopup(
            serverKey: '',
            spaceId: 's',
            query: 'p',
            onPick: (c) => picked = c,
          ),
          overrides: [
            spaceCommandsControllerProvider(
              '',
              's',
            ).overrideWith(() => _Commands([_play(), _skip()])),
          ],
        ),
      );
      expect(find.text('/play'), findsOneWidget);
      expect(find.text('/skip'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('command-play')));
      expect(picked?.name, 'play');
    });

    testWidgets('the form checks options before running', (tester) async {
      final runs = <List<Map<String, dynamic>>>[];
      var cancelled = false;
      await tester.pumpWidget(
        wrap(
          CommandForm(
            serverKey: '',
            spaceId: 's',
            command: _play(),
            onRun: (options) async {
              runs.add(options);
              return null;
            },
            onCancel: () => cancelled = true,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('command-run')));
      await tester.pump();
      expect(find.text('query is required'), findsOneWidget);
      expect(runs, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('command-option-query')),
        'around the world',
      );
      await tester.enterText(
        find.byKey(const ValueKey('command-option-volume')),
        '50',
      );
      await tester.tap(find.byKey(const Key('command-run')));
      await tester.pump();
      expect(runs.single, [
        {'name': 'query', 'value': 'around the world'},
        {'name': 'volume', 'value': 50},
      ]);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancelled, isTrue);
    });

    testWidgets('a button sends the component interaction and spins', (
      tester,
    ) async {
      final requests = <http.Request>[];
      final server = AccordServer.fromBaseUrl('https://accord.example.test');
      final client = AccordClient(
        token: 't',
        baseUrl: server.baseUrl,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'data': {'id': 'i-1'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final message = AccordMessage.fromJson({
        'id': 'm1',
        'channel_id': 'c1',
        'author_id': 'bot',
        'content': 'Now playing',
        'components': [
          {
            'type': 'action_row',
            'components': [
              {
                'type': 'button',
                'style': 'primary',
                'label': 'Pause',
                'custom_id': 'pause',
              },
            ],
          },
        ],
      });
      await tester.pumpWidget(
        wrap(
          MessageComponentsView(message: message),
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
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('component-pause')));
      await tester.pump();
      await tester.pump();
      final body = jsonDecode(requests.single.body) as Map;
      expect(body['type'], 'message_component');
      expect(body['message_id'], 'm1');
      expect(body['data'], {'custom_id': 'pause'});
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // The tracker's timeout would fail it later; settle it now.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MessageComponentsView)),
      );
      container.read(interactionTrackerProvider.notifier).succeeded('i-1');
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('typing /play text in the message box runs the command', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    final client = AccordClient(
      token: 'token',
      baseUrl: server.baseUrl,
      httpClient: MockClient((request) async {
        requests.add(request);
        final body = request.url.path.endsWith('/interactions')
            ? {
                'data': {'id': 'i-9'},
              }
            : request.url.path.endsWith('/messages')
            ? []
            : {'data': {}};
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final channel = AccordChannel(
      id: 'channel',
      spaceId: 'space',
      name: 'general',
    );
    final space = AccordSpace(
      id: 'space',
      ownerId: 'owner',
      roles: [
        AccordRole(
          id: 'everyone',
          name: '@everyone',
          position: 0,
          permissions: const [AccordPermission.sendMessages],
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(
            client: client,
            session: AccordSession(
              server: server,
              token: 'token',
              userId: 'self',
              username: 'Self',
            ),
          ),
        ),
        settingsControllerProvider.overrideWith(_FakeSettings.new),
        spacesControllerProvider.overrideWithValue([space]),
        accordMembersControllerProvider('', 'space').overrideWithValue({
          'self': AccordMember(userId: 'self', spaceId: 'space'),
        }),
        spaceCommandsControllerProvider(
          '',
          'space',
        ).overrideWith(() => _Commands([_play(), _skip()])),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(
            body: MessagePane(
              channel: channel,
              channelId: 'channel',
              spaceId: 'space',
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Typing "/" offers the commands.
    await tester.enterText(find.byType(TextField).last, '/');
    await tester.pump();
    expect(find.byKey(const Key('command-popup')), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).last,
      '/play around the world',
    );
    await tester.testTextInput.receiveAction(TextInputAction.send);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final call = requests.lastWhere(
      (r) => r.url.path.endsWith('/interactions'),
    );
    final body = jsonDecode(call.body) as Map;
    expect(body['command_id'], 'cmd-play');
    expect(body['data']['options'], [
      {'name': 'query', 'value': 'around the world'},
    ]);
    expect(find.text('Sending /play…'), findsOneWidget);
    container.read(interactionTrackerProvider.notifier).succeeded('i-9');
    await tester.pump();
    expect(find.text('Sending /play…'), findsNothing);
    // Nothing was posted as a plain message.
    expect(
      requests.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/messages'),
      ),
      isEmpty,
    );
  });
}
