import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/custom_keybind.dart';
import 'package:bonfire/features/spaces/utils/home_shortcuts.dart';
import 'package:bonfire/features/spaces/views/keyboard_shortcuts_dialog.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Settings › Keybinds: the user's own keybinds (pick an action, record a
/// chord, remove), push-to-talk, and the built-in chords, each of which can
/// be re-recorded, removed or restored.
class KeybindsSection extends ConsumerWidget {
  const KeybindsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final keybinds = settings.keybinds;
    final disabled = settings.disabledDefaultKeybinds.toSet();
    final mac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

    void replace(int index, CustomKeybind keybind) {
      final next = [...keybinds];
      next[index] = keybind;
      controller.setKeybinds(next);
    }

    /// Re-records a built-in: its chord is replaced by the recorded one (kept
    /// with the user's keybinds) and the built-in chord stops working.
    void overrideBuiltIn(HomeShortcut shortcut, CustomKeybind recorded) {
      controller.setKeybinds([
        for (final k in keybinds)
          if (k.action != shortcut.name) k,
        recorded,
      ]);
      controller.setDisabledDefaultKeybinds({...disabled, shortcut.name});
    }

    void removeBuiltIn(HomeShortcut shortcut) =>
        controller.setDisabledDefaultKeybinds({...disabled, shortcut.name});

    void restoreBuiltIn(HomeShortcut shortcut) {
      controller.setKeybinds([
        for (final k in keybinds)
          if (k.action != shortcut.name) k,
      ]);
      controller.setDisabledDefaultKeybinds(
        disabled.where((name) => name != shortcut.name),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Keybinds'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Pick an action, then record the keys you want for it. Your '
            'keybinds win over the built-in ones when they clash.',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
          ),
        ),
        for (final (index, keybind) in keybinds.indexed)
          _KeybindRow(
            key: ValueKey('keybind-$index'),
            keybind: keybind,
            mac: mac,
            onAction: (action) =>
                replace(index, keybind.copyWith(action: action)),
            onRecorded: (recorded) => replace(index, recorded),
            onRemove: () => controller.setKeybinds([
              for (final (i, k) in keybinds.indexed)
                if (i != index) k,
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              key: const Key('keybinds-add'),
              onPressed: () => controller.setKeybinds([
                ...keybinds,
                CustomKeybind(action: HomeShortcut.quickSwitcher.name),
              ]),
              icon: const Icon(Icons.add),
              label: const Text('Add a keybind'),
            ),
          ),
        ),
        const Divider(height: 24),
        ListTile(
          leading: Icon(Icons.mic_none, color: colors.dirtyWhite),
          title: const Text('Push to talk'),
          subtitle: Text(
            settings.pushToTalk
                ? 'Hold ${settings.pushToTalkKeyLabel} to talk'
                : 'Off — turn it on in Voice & video settings',
          ),
          trailing: TextButton(
            onPressed: () => showVoiceSettings(context),
            child: const Text('Change'),
          ),
        ),
        const Divider(height: 24),
        SectionHeader('Built-in keybinds'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            "Record a different chord for any of them, remove one you don't "
            'want, or restore the original.',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
          ),
        ),
        for (final binding in homeShortcutBindings)
          _BuiltInRow(
            key: ValueKey('builtin-${binding.shortcut.name}'),
            binding: binding,
            mac: mac,
            disabled: disabled.contains(binding.shortcut.name),
            replacement: keybinds.lastWhere(
              (k) => k.action == binding.shortcut.name && k.isRecorded,
              orElse: () => const CustomKeybind(action: ''),
            ),
            onRecorded: (recorded) =>
                overrideBuiltIn(binding.shortcut, recorded),
            onRemove: () => removeBuiltIn(binding.shortcut),
            onRestore: () => restoreBuiltIn(binding.shortcut),
          ),
        for (final (chord, label) in composerShortcutRows)
          ListTile(dense: true, title: Text(label), trailing: _Chip(chord)),
        ListTile(
          leading: Icon(Icons.list_alt_outlined, color: colors.dirtyWhite),
          title: const Text('Show the shortcuts in force'),
          subtitle: const Text('Also on Ctrl+/ anywhere in the app'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showKeyboardShortcutsDialog(context),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.muted = false});
  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.foreground,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
          fontFamily: 'monospace',
          color: muted ? colors.gray : null,
          decoration: muted ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

/// A built-in chord with Record / Remove / Restore.
class _BuiltInRow extends StatelessWidget {
  const _BuiltInRow({
    super.key,
    required this.binding,
    required this.mac,
    required this.disabled,
    required this.replacement,
    required this.onRecorded,
    required this.onRemove,
    required this.onRestore,
  });

  final HomeShortcutBinding binding;
  final bool mac;
  final bool disabled;

  /// The user's recorded replacement for this action (empty action when
  /// there is none).
  final CustomKeybind replacement;
  final ValueChanged<CustomKeybind> onRecorded;
  final VoidCallback onRemove;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final replaced = replacement.isRecorded && disabled;
    final chord = replaced
        ? HomeShortcutBinding.describeChord(
            keyLabel: replacement.keyLabel,
            control: replacement.control,
            shift: replacement.shift,
            alt: replacement.alt,
            mac: mac,
          )
        : binding.describe(mac: mac);
    return ListTile(
      dense: true,
      title: Text(binding.label),
      subtitle: replaced
          ? Text('Built-in ${binding.describe(mac: mac)} replaced')
          : disabled
          ? const Text('Removed')
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Chip(chord, muted: disabled && !replaced),
          const SizedBox(width: 4),
          _RecordButton(
            key: ValueKey('builtin-record-${binding.shortcut.name}'),
            tooltip: 'Record a different chord',
            compact: true,
            onRecorded: (recorded) => onRecorded(
              CustomKeybind(
                action: binding.shortcut.name,
                keyId: recorded.keyId,
                physicalKey: recorded.physicalKey,
                keyLabel: recorded.keyLabel,
                control: recorded.control,
                shift: recorded.shift,
                alt: recorded.alt,
              ),
            ),
          ),
          if (disabled)
            IconButton(
              key: ValueKey('builtin-restore-${binding.shortcut.name}'),
              tooltip: 'Restore the built-in chord',
              onPressed: onRestore,
              icon: Icon(Icons.restart_alt, size: 18, color: colors.gray),
            )
          else
            IconButton(
              key: ValueKey('builtin-remove-${binding.shortcut.name}'),
              tooltip: 'Remove this keybind',
              onPressed: onRemove,
              icon: Icon(Icons.close, size: 18, color: colors.gray),
            ),
        ],
      ),
    );
  }
}

/// One of the user's keybinds: action picker, record button, remove.
class _KeybindRow extends StatelessWidget {
  const _KeybindRow({
    super.key,
    required this.keybind,
    required this.mac,
    required this.onAction,
    required this.onRecorded,
    required this.onRemove,
  });

  final CustomKeybind keybind;
  final bool mac;
  final ValueChanged<String> onAction;
  final ValueChanged<CustomKeybind> onRecorded;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final chord = keybind.isRecorded
        ? HomeShortcutBinding.describeChord(
            keyLabel: keybind.keyLabel,
            control: keybind.control,
            shift: keybind.shift,
            alt: keybind.alt,
            mac: mac,
          )
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: keybind.action,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Action',
                isDense: true,
              ),
              items: [
                for (final shortcut in HomeShortcut.values)
                  DropdownMenuItem(
                    value: shortcut.name,
                    child: Text(homeShortcutLabel(shortcut)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) onAction(value);
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: _RecordButton(
              key: ValueKey('keybind-record-${keybind.action}'),
              label: chord ?? 'Record keybind',
              onRecorded: (recorded) => onRecorded(
                keybind.copyWith(
                  keyId: recorded.keyId,
                  physicalKey: recorded.physicalKey,
                  keyLabel: recorded.keyLabel,
                  control: recorded.control,
                  shift: recorded.shift,
                  alt: recorded.alt,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: Icon(Icons.close, color: colors.gray),
          ),
        ],
      ),
    );
  }
}

/// A chord captured by [_RecordButton].
class _Chord {
  const _Chord({
    required this.keyId,
    required this.physicalKey,
    required this.keyLabel,
    required this.control,
    required this.shift,
    required this.alt,
  });
  final int keyId;
  final int physicalKey;
  final String keyLabel;
  final bool control;
  final bool shift;
  final bool alt;
}

/// "Record keybind": while recording, the first non-modifier key pressed
/// becomes the chord with whatever modifiers are held; Escape cancels. The
/// event is consumed so the app's own shortcuts don't fire meanwhile.
class _RecordButton extends StatefulWidget {
  const _RecordButton({
    super.key,
    required this.onRecorded,
    this.label,
    this.tooltip,
    this.compact = false,
  });

  final ValueChanged<_Chord> onRecorded;
  final String? label;
  final String? tooltip;

  /// Icon only (the built-in rows), instead of a labelled button.
  final bool compact;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton> {
  bool _recording = false;

  static final _modifierKeys = <LogicalKeyboardKey>{
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
  };

  @override
  void dispose() {
    if (_recording) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _start() {
    if (_recording) return;
    setState(() => _recording = true);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _stop() {
    if (!_recording) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (mounted) setState(() => _recording = false);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return true;
    final key = event.logicalKey;
    if (_modifierKeys.contains(key)) return true;
    if (key == LogicalKeyboardKey.escape) {
      _stop();
      return true;
    }
    final mods = HardwareKeyboard.instance;
    widget.onRecorded(
      _Chord(
        keyId: key.keyId,
        physicalKey: event.physicalKey.usbHidUsage,
        keyLabel: keybindKeyLabel(event),
        control: mods.isControlPressed || mods.isMetaPressed,
        shift: mods.isShiftPressed,
        alt: mods.isAltPressed,
      ),
    );
    _stop();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final icon = Icon(
      _recording ? Icons.fiber_manual_record : Icons.keyboard,
      size: widget.compact ? 18 : 16,
      color: _recording ? colors.red : (widget.compact ? colors.gray : null),
    );
    if (widget.compact) {
      return IconButton(
        tooltip: _recording ? 'Press a key… (Esc cancels)' : widget.tooltip,
        onPressed: _recording ? _stop : _start,
        icon: icon,
      );
    }
    return OutlinedButton.icon(
      onPressed: _recording ? _stop : _start,
      icon: icon,
      label: Text(
        _recording ? 'Press a key…' : (widget.label ?? 'Record keybind'),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// How a recorded key is shown: the character it types on the current
/// layout, else the key's name (F-keys, arrows, Space…), else the physical
/// key's name (Ctrl held: no character, and some platforms report an odd
/// logical key).
String keybindKeyLabel(KeyEvent event) {
  final character = event.character?.trim() ?? '';
  if (character.isNotEmpty && character.runes.first >= 0x20) {
    return character.toUpperCase();
  }
  final key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowRight) return '→';
  if (key == LogicalKeyboardKey.space) return 'Space';
  // With Ctrl held, Windows reports a logical key without a label: name the
  // physical key instead (release-safe, unlike `debugName`).
  final physical = physicalKeyName(event.physicalKey.usbHidUsage);
  if (physical != null) return physical;
  if (key.keyLabel.trim().isNotEmpty) return key.keyLabel.toUpperCase();
  return 'Key ${event.physicalKey.usbHidUsage.toRadixString(16)}';
}
