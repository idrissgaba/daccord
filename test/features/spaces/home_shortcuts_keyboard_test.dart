import 'package:bonfire/features/spaces/utils/home_shortcuts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The matcher fed from a real [HardwareKeyboard] state, the way the home
/// screen's hardware-level handler reads it.
void main() {
  HomeShortcut? seen;
  bool handler(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final mods = HardwareKeyboard.instance;
    seen = matchHomeShortcut(
      pressed: event.logicalKey,
      control: mods.isControlPressed || mods.isMetaPressed,
      shift: mods.isShiftPressed,
      alt: mods.isAltPressed,
    );
    return seen != null;
  }

  setUp(() {
    seen = null;
    HardwareKeyboard.instance.addHandler(handler);
  });
  tearDown(() => HardwareKeyboard.instance.removeHandler(handler));

  testWidgets('Ctrl+K reaches the matcher as the quick switcher', (
    tester,
  ) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    expect(seen, HomeShortcut.quickSwitcher);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('Alt+↓ is the next channel, Ctrl+Alt+↓ the next space', (
    tester,
  ) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    expect(seen, HomeShortcut.nextChannel);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    expect(seen, HomeShortcut.nextSpace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  });
}
