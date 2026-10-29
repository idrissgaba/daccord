import 'package:bonfire/features/voice/services/global_key_watcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reports presses and releases of the watched key', (
    tester,
  ) async {
    {
      var held = false;
      final events = <bool>[];
      final watcher = GlobalKeyWatcher(
        supported: true,
        virtualKeyFor: (usage) => usage == 0x70028 ? 0x56 : null,
        isDown: (vk) => vk == 0x56 && held,
      );
      expect(watcher.watch(0x70028, events.add), isTrue);
      await tester.pump(const Duration(milliseconds: 50));
      held = true;
      await tester.pump(const Duration(milliseconds: 50));
      held = false;
      await tester.pump(const Duration(milliseconds: 50));
      expect(events, [true, false]);
      watcher.stop();
      expect(watcher.watching, isFalse);
    }
  });

  test('refuses unknown keys and unsupported platforms', () {
    final unknown = GlobalKeyWatcher(
      supported: true,
      virtualKeyFor: (_) => null,
      isDown: (_) => false,
    );
    expect(unknown.watch(1, (_) {}), isFalse);
    final web = GlobalKeyWatcher(
      supported: false,
      virtualKeyFor: (_) => 1,
      isDown: (_) => false,
    );
    expect(web.watch(1, (_) {}), isFalse);
    expect(web.watching, isFalse);
  });

  testWidgets('fires a chord once per press, only with its exact modifiers', (
    tester,
  ) async {
    final held = <int>{};
    final pressed = <String>[];
    final watcher = GlobalChordWatcher<String>(
      supported: true,
      virtualKeyFor: (usage) => usage == 0x70010 ? 0x4D : null,
      isDown: held.contains,
    );
    expect(
      watcher.watch({
        'mute': const GlobalChord(0x70010, control: true, shift: true),
      }, pressed.add),
      isTrue,
    );
    // M alone, then Ctrl+M: not the chord.
    held.add(0x4D);
    await tester.pump(const Duration(milliseconds: 50));
    held.add(0x11);
    await tester.pump(const Duration(milliseconds: 50));
    expect(pressed, isEmpty);
    // Ctrl+Shift+M held across several samples fires once.
    held.add(0x10);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(pressed, ['mute']);
    // Released and pressed again fires again; Alt added does not match.
    held.remove(0x4D);
    await tester.pump(const Duration(milliseconds: 50));
    held.add(0x4D);
    await tester.pump(const Duration(milliseconds: 50));
    held.add(0x12);
    held.remove(0x4D);
    await tester.pump(const Duration(milliseconds: 50));
    held.add(0x4D);
    await tester.pump(const Duration(milliseconds: 50));
    expect(pressed, ['mute', 'mute']);
    watcher.stop();
    expect(watcher.watching, isFalse);
  });

  test('chords stay focus-only where keys cannot be watched', () {
    final web = GlobalChordWatcher<String>(
      supported: false,
      virtualKeyFor: (_) => 1,
      isDown: (_) => false,
    );
    expect(web.watch({'mute': const GlobalChord(1)}, (_) {}), isFalse);
    final unknown = GlobalChordWatcher<String>(
      supported: true,
      virtualKeyFor: (_) => null,
      isDown: (_) => false,
    );
    expect(unknown.watch({'mute': const GlobalChord(1)}, (_) {}), isFalse);
    expect(unknown.watching, isFalse);
  });
}
