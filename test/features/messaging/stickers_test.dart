import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/space_stickers.dart';
import 'package:bonfire/features/messaging/views/stickers.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Stickers extends SpaceStickersController {
  _Stickers(this.stickers);
  final List<AccordSticker> stickers;
  @override
  List<AccordSticker>? build(String serverKey, String spaceId) => stickers;
}

AccordSticker _sticker(String id, {String? image = '/cdn/emojis/s/x.png'}) =>
    AccordSticker.fromJson({
      'id': id,
      'space_id': 's1',
      'name': 'Party $id',
      'image': image,
      'format': 'png',
    });

void main() {
  test('a message carries its sticker', () {
    final message = AccordMessage.fromJson({
      'id': 'm',
      'channel_id': 'c',
      'author_id': 'u',
      'content': '',
      'stickers': [
        {'id': 'st', 'name': 'Party', 'image': '/cdn/emojis/s/st.png'},
      ],
    });
    expect(message.stickers.single.name, 'Party');
    expect(message.toJson()['stickers'], hasLength(1));
  });

  test('sticker images resolve against the CDN, deleted ones to null', () {
    expect(
      stickerUrl(_sticker('a'), 'https://chat.example/cdn'),
      'https://chat.example/cdn/emojis/s/x.png',
    );
    expect(
      stickerUrl(_sticker('b', image: null), 'https://chat.example'),
      isNull,
    );
  });

  test('the controller upserts and removes', () {
    final container = ProviderContainer(
      overrides: [
        spaceStickersControllerProvider(
          'k',
          's1',
        ).overrideWith(() => _Stickers([_sticker('a')])),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      spaceStickersControllerProvider('k', 's1').notifier,
    );
    controller.upsert(_sticker('b'));
    controller.upsert(
      AccordSticker.fromJson({'id': 'a', 'name': 'Renamed', 'image': '/x.png'}),
    );
    final names = container
        .read(spaceStickersControllerProvider('k', 's1'))!
        .map((s) => s.name);
    expect(names, ['Renamed', 'Party b']);
    controller.remove('a');
    expect(
      container.read(spaceStickersControllerProvider('k', 's1')),
      hasLength(1),
    );
  });

  testWidgets('the picker offers each space and returns the tapped sticker', (
    tester,
  ) async {
    final server = AccordServer.fromBaseUrl('https://chat.example');
    final client = AccordClient(token: 't', baseUrl: server.baseUrl);
    addTearDown(client.dispose);
    AccordSticker? picked;
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
          spacesControllerProvider.overrideWithValue([
            AccordSpace(id: 's0', name: 'Other'),
            AccordSpace(id: 's1', name: 'Home'),
          ]),
          spaceStickersControllerProvider(
            '',
            's1',
          ).overrideWith(() => _Stickers([_sticker('a')])),
          spaceStickersControllerProvider(
            '',
            's0',
          ).overrideWith(() => _Stickers(const [])),
        ],
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await showStickerPicker(context, spaceId: 's1'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The current space comes first.
    final tabs = tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text);
    expect(tabs, ['Home', 'Other']);
    await tester.tap(find.byKey(const ValueKey('sticker-a')));
    await tester.pumpAndSettle();
    expect(picked?.id, 'a');
  });
}
