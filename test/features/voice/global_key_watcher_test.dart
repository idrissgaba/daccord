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
}
