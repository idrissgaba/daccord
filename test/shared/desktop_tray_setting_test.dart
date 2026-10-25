import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('closing hides to the tray by default and the choice persists', () {
    const settings = AccordSettings();
    expect(settings.closeToTray, isTrue);
    final off = settings.copyWith(closeToTray: false);
    expect(AccordSettings.fromJson(off.toJson()).closeToTray, isFalse);
    expect(AccordSettings.fromJson(const {}).closeToTray, isTrue);
  });
}
