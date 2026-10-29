/// App-wide keyboard shortcuts of the home screen, kept as data so the
/// matcher, the "Keyboard shortcuts" dialog and the tests read one table.
library;

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/settings/models/custom_keybind.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';

/// What a home-screen shortcut does.
enum HomeShortcut {
  quickSwitcher,
  previousChannel,
  nextChannel,
  previousSpace,
  nextSpace,
  toggleMute,
  toggleDeafen,
  toggleMembers,
  openSettings,
  showShortcuts,
}

/// One row of the shortcuts table: the chord and what it does.
class HomeShortcutBinding {
  const HomeShortcutBinding(
    this.shortcut,
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    required this.label,
    this.keyLabel = '',
    this.physical = 0,
  });

  final HomeShortcut shortcut;
  final LogicalKeyboardKey key;

  /// The main key as the layout that recorded it showed it (recorded
  /// keybinds only); built-ins derive it from [key].
  final String keyLabel;

  /// `PhysicalKeyboardKey.usbHidUsage` of a recorded key (0 for built-ins):
  /// a press matches on either the logical or the physical key.
  final int physical;

  /// Ctrl on Windows/Linux, ⌘ on macOS (the matcher treats Meta as Control).
  final bool control;
  final bool shift;
  final bool alt;
  final String label;

  bool matches({
    required LogicalKeyboardKey pressed,
    required bool control,
    required bool shift,
    required bool alt,
    int physicalPressed = 0,
  }) =>
      (pressed == key || (physical != 0 && physicalPressed == physical)) &&
      control == this.control &&
      shift == this.shift &&
      alt == this.alt;

  /// "Ctrl+Shift+M" style text for the dialog and the settings page.
  String describe({bool mac = false}) {
    final parts = <String>[
      if (control) mac ? '⌘' : 'Ctrl',
      if (alt) mac ? '⌥' : 'Alt',
      if (shift) mac ? '⇧' : 'Shift',
      keyLabel.isNotEmpty ? keyLabel : _keyName(key),
    ];
    return parts.join('+');
  }

  /// "Ctrl+Shift+M" style text for a chord that is still being composed.
  static String describeChord({
    required String keyLabel,
    required bool control,
    required bool shift,
    required bool alt,
    bool mac = false,
  }) => [
    if (control) mac ? '⌘' : 'Ctrl',
    if (alt) mac ? '⌥' : 'Alt',
    if (shift) mac ? '⇧' : 'Shift',
    keyLabel,
  ].join('+');

  static String _keyName(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.slash) return '/';
    if (key == LogicalKeyboardKey.comma) return ',';
    return key.keyLabel.toUpperCase();
  }
}

/// The bindings, in the order the dialog lists them. Chords follow the
/// defaults users know from other chat apps.
const List<HomeShortcutBinding> homeShortcutBindings = [
  HomeShortcutBinding(
    HomeShortcut.quickSwitcher,
    LogicalKeyboardKey.keyK,
    control: true,
    label: 'Find or jump to a channel',
  ),
  HomeShortcutBinding(
    HomeShortcut.previousChannel,
    LogicalKeyboardKey.arrowUp,
    alt: true,
    label: 'Previous channel',
  ),
  HomeShortcutBinding(
    HomeShortcut.nextChannel,
    LogicalKeyboardKey.arrowDown,
    alt: true,
    label: 'Next channel',
  ),
  HomeShortcutBinding(
    HomeShortcut.previousSpace,
    LogicalKeyboardKey.arrowUp,
    control: true,
    alt: true,
    label: 'Previous space',
  ),
  HomeShortcutBinding(
    HomeShortcut.nextSpace,
    LogicalKeyboardKey.arrowDown,
    control: true,
    alt: true,
    label: 'Next space',
  ),
  HomeShortcutBinding(
    HomeShortcut.toggleMute,
    LogicalKeyboardKey.keyM,
    control: true,
    shift: true,
    label: 'Mute or unmute your microphone',
  ),
  HomeShortcutBinding(
    HomeShortcut.toggleDeafen,
    LogicalKeyboardKey.keyD,
    control: true,
    shift: true,
    label: 'Deafen or undeafen',
  ),
  HomeShortcutBinding(
    HomeShortcut.toggleMembers,
    LogicalKeyboardKey.keyU,
    control: true,
    label: 'Show or hide the member list',
  ),
  HomeShortcutBinding(
    HomeShortcut.openSettings,
    LogicalKeyboardKey.comma,
    control: true,
    label: 'Open settings',
  ),
  HomeShortcutBinding(
    HomeShortcut.showShortcuts,
    LogicalKeyboardKey.slash,
    control: true,
    label: 'Show this list',
  ),
];

/// Shortcuts the composer and the inline editor handle themselves, listed
/// in the dialog for completeness.
const List<(String chord, String label)> composerShortcutRows = [
  ('Enter', 'Send the message, or save an edit'),
  ('Shift+Enter', 'New line'),
  ('↑', 'Edit your last message (empty composer)'),
  ('Escape', 'Cancel a reply, an edit or the mention list'),
  ('Tab / Enter', 'Insert the highlighted @mention'),
  ('Ctrl+V', 'Paste an image or a long text as an attachment'),
];

/// A readable name for a physical key (its USB HID usage), for recorded
/// chords whose logical key has no label (Ctrl held on Windows reports an
/// odd logical key, and `PhysicalKeyboardKey.debugName` is debug-only).
/// Null for keys this table doesn't know.
String? physicalKeyName(int usbHidUsage) {
  const page = 0x00070000;
  if (usbHidUsage < page || usbHidUsage > page + 0xFF) return null;
  final usage = usbHidUsage - page;
  if (usage >= 0x04 && usage <= 0x1D) {
    return String.fromCharCode(0x41 + usage - 0x04); // A–Z
  }
  if (usage >= 0x1E && usage <= 0x26) return '${usage - 0x1D}'; // 1–9
  if (usage == 0x27) return '0';
  if (usage >= 0x3A && usage <= 0x45) return 'F${usage - 0x39}'; // F1–F12
  if (usage >= 0x68 && usage <= 0x73) return 'F${usage - 0x5B}'; // F13–F24
  return switch (usage) {
    0x28 => 'Enter',
    0x29 => 'Esc',
    0x2A => 'Backspace',
    0x2B => 'Tab',
    0x2C => 'Space',
    0x2D => '-',
    0x2E => '=',
    0x2F => '[',
    0x30 => ']',
    0x31 => '\\',
    0x33 => ';',
    0x34 => "'",
    0x35 => '`',
    0x36 => ',',
    0x37 => '.',
    0x38 => '/',
    0x39 => 'Caps Lock',
    0x46 => 'Print Screen',
    0x47 => 'Scroll Lock',
    0x48 => 'Pause',
    0x49 => 'Insert',
    0x4A => 'Home',
    0x4B => 'Page Up',
    0x4C => 'Delete',
    0x4D => 'End',
    0x4E => 'Page Down',
    0x4F => '→',
    0x50 => '←',
    0x51 => '↓',
    0x52 => '↑',
    0x54 => 'Numpad /',
    0x55 => 'Numpad *',
    0x56 => 'Numpad -',
    0x57 => 'Numpad +',
    0x58 => 'Numpad Enter',
    0x63 => 'Numpad .',
    _ => usage >= 0x59 && usage <= 0x62
        ? 'Numpad ${usage == 0x62 ? 0 : usage - 0x58}'
        : null,
  };
}

/// What the Keybinds page calls each action.
String homeShortcutLabel(HomeShortcut shortcut) => homeShortcutBindings
    .firstWhere((b) => b.shortcut == shortcut)
    .label;

/// The built-in chord of [shortcut].
HomeShortcutBinding defaultBindingFor(HomeShortcut shortcut) =>
    homeShortcutBindings.firstWhere((b) => b.shortcut == shortcut);

/// A recorded keybind as a binding, or null while it has no key yet or names
/// an action this build doesn't know.
HomeShortcutBinding? bindingFromCustom(CustomKeybind keybind) {
  if (!keybind.isRecorded) return null;
  final shortcut = HomeShortcut.values.firstWhereOrNull(
    (s) => s.name == keybind.action,
  );
  if (shortcut == null) return null;
  return HomeShortcutBinding(
    shortcut,
    LogicalKeyboardKey.findKeyByKeyId(keybind.keyId) ??
        LogicalKeyboardKey(keybind.keyId),
    control: keybind.control,
    shift: keybind.shift,
    alt: keybind.alt,
    label: homeShortcutLabel(shortcut),
    keyLabel: keybind.keyLabel,
    physical: keybind.physicalKey,
  );
}

/// The bindings in force: the user's recorded ones first (they win when a
/// chord clashes with a built-in one), then the built-ins the user hasn't
/// removed ([disabledDefaults] holds their `HomeShortcut.name`s).
List<HomeShortcutBinding> effectiveBindings(
  List<CustomKeybind> custom, {
  Iterable<String> disabledDefaults = const [],
}) {
  final disabled = disabledDefaults.toSet();
  return [
    for (final keybind in custom)
      if (bindingFromCustom(keybind) case final binding?) binding,
    for (final binding in homeShortcutBindings)
      if (!disabled.contains(binding.shortcut.name)) binding,
  ];
}

/// The binding [pressed] with these modifiers triggers, or null. [custom]
/// are the user's recorded keybinds, checked before the built-ins.
HomeShortcut? matchHomeShortcut({
  required LogicalKeyboardKey pressed,
  required bool control,
  required bool shift,
  required bool alt,
  int physicalPressed = 0,
  List<CustomKeybind> custom = const [],
  Iterable<String> disabledDefaults = const [],
}) {
  for (final binding in effectiveBindings(
    custom,
    disabledDefaults: disabledDefaults,
  )) {
    if (binding.matches(
      pressed: pressed,
      control: control,
      shift: shift,
      alt: alt,
      physicalPressed: physicalPressed,
    )) {
      return binding.shortcut;
    }
  }
  return null;
}

/// Channel ids in the order the channel list shows them: uncategorised
/// channels first, then each category's children. Categories themselves are
/// skipped (they can't be opened); collapsed ones are still walked, as in the
/// reference client.
List<String> orderedNavigableChannelIds(List<AccordChannel> channels) {
  final categories = channels.where((c) => c.type == 'category');
  final leaves = channels.where((c) => c.type != 'category');
  final byParent = <String?, List<String>>{};
  for (final c in leaves) {
    byParent.putIfAbsent(c.parentId, () => []).add(c.id);
  }
  return [
    ...?byParent[null],
    for (final category in categories) ...?byParent[category.id],
  ];
}

/// [ids] in [savedOrder] first, then the rest in their given order — the
/// rail's ordering, shared so ↑/↓ across spaces follow what is drawn.
List<String> orderBySavedOrder(List<String> ids, List<String> savedOrder) {
  final idSet = ids.toSet();
  final inOrder = [
    for (final id in savedOrder)
      if (idSet.contains(id)) id,
  ];
  final placed = inOrder.toSet();
  final rest = [
    for (final id in ids)
      if (!placed.contains(id)) id,
  ];
  return [...inOrder, ...rest];
}

/// The id after (or before) [current] in [ids], wrapping at either end. With
/// no [current] in the list, the first (or last) id. Null when [ids] is empty.
String? adjacentId(List<String> ids, String? current, {required bool forward}) {
  if (ids.isEmpty) return null;
  final index = current == null ? -1 : ids.indexOf(current);
  if (index < 0) return forward ? ids.first : ids.last;
  return ids[(index + (forward ? 1 : -1)) % ids.length];
}
