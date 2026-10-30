import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isNewerVersion with build numbers', () {
    test('a higher build of the same version is newer', () {
      expect(isNewerVersion('0.2.27.14', '0.2.27.13'), isTrue);
      expect(isNewerVersion('v0.2.27.14', '0.2.27+13'), isTrue);
      expect(isNewerVersion('0.2.27+14', '0.2.27.13'), isTrue);
    });

    test('the same or a lower build is not', () {
      expect(isNewerVersion('0.2.27.13', '0.2.27.13'), isFalse);
      expect(isNewerVersion('0.2.27.12', '0.2.27.13'), isFalse);
      expect(isNewerVersion('0.2.27', '0.2.27.13'), isFalse);
    });

    test('the version core still wins over the build', () {
      expect(isNewerVersion('0.2.28', '0.2.27.13'), isTrue);
      expect(isNewerVersion('0.3.0', '0.2.27.99'), isTrue);
      expect(isNewerVersion('0.2.26.99', '0.2.27'), isFalse);
    });

    test('prerelease suffixes are ignored for the comparison', () {
      expect(isNewerVersion('0.2.28-beta.1', '0.2.27.13'), isTrue);
      expect(isNewerVersion('0.2.27.14-rc.1', '0.2.27.13'), isTrue);
    });
  });
}
