import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('emojiSuggestionsFor', () {
    test('ranks short-name prefixes first, then keyword matches', () {
      final picks = emojiSuggestionsFor(
        'thu',
        custom: const [],
        cdnUrl: null,
        tone: 0,
      );
      expect(picks, isNotEmpty);
      expect(picks.first.name, startsWith('thu'));
      expect(picks.length, lessThanOrEqualTo(10));
    });

    test('custom space emoji come before unicode ones', () {
      final picks = emojiSuggestionsFor(
        'par',
        custom: [AccordEmoji(id: '1', name: 'party_blob')],
        cdnUrl: 'https://cdn.example',
        tone: 0,
      );
      expect(picks.first.isCustom, isTrue);
      expect(picks.first.composerText, ':party_blob:');
    });

    test('applies the skin tone where the emoji has one', () {
      final picks = emojiSuggestionsFor(
        'thumbsup',
        custom: const [],
        cdnUrl: null,
        tone: 2,
      );
      expect(picks.first.char, '👍🏼');
    });

    test('an empty query suggests nothing', () {
      expect(
        emojiSuggestionsFor('', custom: const [], cdnUrl: null, tone: 0),
        isEmpty,
      );
    });
  });
}
