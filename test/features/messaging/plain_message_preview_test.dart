import 'package:bonfire/features/messaging/utils/message_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drops inline markdown markers', () {
    expect(
      plainMessagePreview('QA test 1 **gras** _italique_ ~~barré~~ `code`'),
      'QA test 1 gras italique barré code',
    );
  });

  test('turns shortcodes into emoji and keeps unknown ones', () {
    expect(plainMessagePreview(':smile: hi :nope_nope:'), '😄 hi :nope_nope:');
  });

  test('flattens headings, quotes, masked links and code fences', () {
    expect(
      plainMessagePreview('# Titre\n> cité\n[lien](https://a.b) ```dart\nx()```'),
      'Titre cité lien x()',
    );
  });

  test('keeps spoilers hidden', () {
    expect(plainMessagePreview('voilà ||secret||'), 'voilà (spoiler)');
  });
}
