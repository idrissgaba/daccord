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
/// chord, remove), push-to-talk, and the built-in chords for reference.
class KeybindsSection extends ConsumerWidget {
  const KeybindsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final keybinds = settings.keybinds;
    final mac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

    void replace(int index, CustomKeybind keybind) {
      final next = [...keybinds];
      next[index] = keybind;
      controller.setKeybinds(next);
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
        for (final binding in homeShortcutBindings)
          ListTile(
            dense: true,
            title: Text(binding.label),
            trailing: _Chip(binding.describe(mac: mac)),
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
  const _Chip(this.text);
  final String text;

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
        style: Theme.of(
          context,
        ).textTheme.labelMedium!.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

/// One keybind: action picker, "Record keybind" button, remove.
class _KeybindRow extends StatefulWidget {
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
  State<_KeybindRow> createState() => _KeybindRowState();
}

class _KeybindRowState extends State<_KeybindRow> {
  bool _recording = false;

  @override
  void dispose() {
    if (_recording) HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _startRecording() {
    if (_recording) return;
    setState(() => _recording = true);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  void _stopRecording() {
    if (!_recording) return;
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (mounted) setState(() => _recording = false);
  }

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

  /// The first non-modifier key pressed becomes the chord, with whatever
  /// modifiers are held. Escape cancels. The event is consumed so the app's
  /// shortcuts don't fire while a chord is being recorded.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return true;
    final key = event.logicalKey;
    if (_modifierKeys.contains(key)) return true;
    if (key == LogicalKeyboardKey.escape) {
      _stopRecording();
      return true;
    }
    final mods = HardwareKeyboard.instance;
    widget.onRecorded(
      widget.keybind.copyWith(
        keyId: key.keyId,
        physicalKey: event.physicalKey.usbHidUsage,
        keyLabel: keybindKeyLabel(event),
        control: mods.isControlPressed || mods.isMetaPressed,
        shift: mods.isShiftPressed,
        alt: mods.isAltPressed,
      ),
    );
    _stopRecording();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final keybind = widget.keybind;
    final chord = _recording
        ? 'Press a key…'
        : keybind.isRecorded
        ? HomeShortcutBinding.describeChord(
            keyLabel: keybind.keyLabel,
            control: keybind.control,
            shift: keybind.shift,
            alt: keybind.alt,
            mac: widget.mac,
          )
        : 'Record keybind';
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
                if (value != null) widget.onAction(value);
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: OutlinedButton.icon(
              key: ValueKey('keybind-record-${keybind.action}'),
              onPressed: _recording ? _stopRecording : _startRecording,
              icon: Icon(
                _recording ? Icons.fiber_manual_record : Icons.keyboard,
                size: 16,
                color: _recording ? colors.red : null,
              ),
              label: Text(chord, overflow: TextOverflow.ellipsis),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: widget.onRemove,
            icon: Icon(Icons.close, color: colors.gray),
          ),
        ],
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
  if (key.keyLabel.trim().isNotEmpty) return key.keyLabel.toUpperCase();
  final physical = event.physicalKey.debugName ?? '';
  if (physical.isNotEmpty) return physical.replaceFirst(RegExp(r'^Key '), '');
  return 'Key ${event.physicalKey.usbHidUsage.toRadixString(16)}';
}
