import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the generated emoji catalogue', () {
    test('covers the whole unicode set', () {
      expect(kEmojiCatalog.length, greaterThan(1800));
      for (final category in EmojiCategory.values) {
        expect(
          kEmojiCatalog.where((e) => e.category == category),
          isNotEmpty,
          reason: 'no ${category.label} emoji',
        );
      }
    });

    test('short names are unique and lower-case', () {
      final seen = <String>{};
      for (final e in kEmojiCatalog) {
        expect(e.char, isNotEmpty);
        expect(e.name, matches(RegExp(r'^[a-z0-9_+-]+$')), reason: e.name);
        expect(seen.add(e.name), isTrue, reason: 'duplicate ${e.name}');
      }
    });

    test('keeps the curated short names', () {
      expect(resolveEmojiGlyph(':joy:'), '😂');
      expect(resolveEmojiGlyph('thumbsup'), '👍');
      expect(resolveEmojiGlyph(':tada:'), '🎉');
      expect(resolveEmojiGlyph(':flag_fr:'), '🇫🇷');
    });

    test('skin tones come in fives and apply to the glyph', () {
      final toned = kEmojiCatalog.where((e) => e.hasTones).toList();
      expect(toned.length, greaterThan(250));
      for (final e in toned) {
        expect(e.tones, hasLength(5), reason: e.name);
      }
      final thumbs = kEmojiCatalog.firstWhere((e) => e.name == 'thumbsup');
      expect(thumbs.withTone(0), '👍');
      expect(thumbs.withTone(1), '👍🏻');
      expect(thumbs.withTone(5), '👍🏿');
      expect(thumbs.withTone(9), '👍');
      final joy = kEmojiCatalog.firstWhere((e) => e.name == 'joy');
      expect(joy.hasTones, isFalse);
      expect(joy.withTone(3), '😂');
    });

    test('search matches names and keywords', () {
      expect(kEmojiCatalog.where((e) => e.matches('tears')), isNotEmpty);
      expect(
        kEmojiCatalog.where((e) => e.matches('france')).first.char,
        '🇫🇷',
      );
    });
  });
}
