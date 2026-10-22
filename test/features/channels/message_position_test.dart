import 'package:bonfire/features/channels/utils/message_position.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readPositionBefore', () {
    test('is the newest loaded message older than the target', () {
      expect(readPositionBefore(['5', '9', '12', '15'], '12'), '9');
    });

    test('compares numerically, not as text', () {
      expect(readPositionBefore(['99', '100', '101'], '101'), '100');
    });

    test('is "0" when nothing older is loaded', () {
      expect(readPositionBefore(['12', '15'], '12'), '0');
      expect(readPositionBefore(const [], '12'), '0');
    });
  });
}
