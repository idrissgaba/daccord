import 'package:bonfire/features/messaging/views/emoji_picker.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Settings extends SettingsController {
  _Settings(this.initial);
  final AccordSettings initial;
  @override
  AccordSettings build() => initial;
}

Widget _host(
  ValueChanged<EmojiPick> onPick, {
  AccordSettings settings = const AccordSettings(),
}) => ProviderScope(
  overrides: [
    settingsControllerProvider.overrideWith(() => _Settings(settings)),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 432,
          height: 448,
          child: EmojiPickerPanel(onPick: onPick),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('lists every category with a heading and a rail entry', (
    tester,
  ) async {
    await tester.pumpWidget(_host((_) {}));
    await tester.pump();
    expect(find.text('SMILEYS'), findsOneWidget);
    expect(find.byTooltip('Smileys'), findsOneWidget);
    expect(find.byTooltip('Flags'), findsOneWidget);
    expect(find.text('Pick an emoji'), findsOneWidget);
    expect(find.byKey(const Key('emoji-skin-tone')), findsOneWidget);
  });

  testWidgets('search narrows the grid and Enter picks the first hit', (
    tester,
  ) async {
    EmojiPick? picked;
    await tester.pumpWidget(_host((p) => picked = p));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('emoji-picker-search')),
      'thumbsup',
    );
    await tester.pump();
    expect(find.text('👍'), findsOneWidget);
    expect(find.text('SMILEYS'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(picked?.name, 'thumbsup');
    expect(picked?.char, '👍');
    expect(picked?.composerText, '👍');
  });

  testWidgets('the saved skin tone applies to the picked glyph', (
    tester,
  ) async {
    EmojiPick? picked;
    await tester.pumpWidget(
      _host(
        (p) => picked = p,
        settings: const AccordSettings(emojiSkinTone: 5),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('emoji-picker-search')),
      'thumbsup',
    );
    await tester.pump();
    await tester.tap(find.text('👍🏿'));
    await tester.pump();
    expect(picked?.char, '👍🏿');
    expect(picked?.reactionName, '👍🏿');
  });

  testWidgets('an unknown query says so', (tester) async {
    await tester.pumpWidget(_host((_) {}));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('emoji-picker-search')),
      'zzqqxx',
    );
    await tester.pump();
    expect(find.text('No emoji match "zzqqxx"'), findsOneWidget);
  });
}
