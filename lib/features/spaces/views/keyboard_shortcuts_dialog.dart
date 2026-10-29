import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/utils/home_shortcuts.dart';
import 'package:bonfire/shared/components/dialog_title_bar.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists every keyboard shortcut in force (Ctrl+/ and Settings › Keybinds).
/// An action the user recorded a keybind for shows that chord in place of
/// the built-in one.
Future<void> showKeyboardShortcutsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const KeyboardShortcutsDialog(),
  );
}

class KeyboardShortcutsDialog extends ConsumerWidget {
  const KeyboardShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final mac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final custom = ref.watch(
      settingsControllerProvider.select((s) => s.keybinds),
    );
    final effective = effectiveBindings(custom);
    // One row per action: the first binding in force for it.
    final rows = [
      for (final shortcut in HomeShortcut.values)
        effective.firstWhere((b) => b.shortcut == shortcut),
    ];
    Widget row(String chord, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.foreground,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              chord,
              style: theme.textTheme.labelMedium!.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall!.copyWith(color: colors.gray),
      ),
    );
    return Dialog(
      backgroundColor: colors.background,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DialogTitleBar('Keyboard shortcuts'),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading('Navigation and voice'),
                    for (final binding in rows)
                      row(binding.describe(mac: mac), binding.label),
                    heading('Writing'),
                    for (final (chord, label) in composerShortcutRows)
                      row(chord, label),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Change them in Settings › Keybinds.',
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: colors.gray,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
