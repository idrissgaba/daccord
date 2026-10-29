import 'package:bonfire/features/spaces/utils/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSearchQuery', () {
    test('plain text has no filters', () {
      final q = parseSearchQuery('hello world');
      expect(q.text, 'hello world');
      expect(q.hasFilters, isFalse);
    });

    test('reads from:, in:, before:, after: and pinned:', () {
      final q = parseSearchQuery(
        'from:@kingo in:#general before:2026-10-30 after:2026-10-01 '
        'pinned:true plan',
      );
      expect(q.text, 'plan');
      expect(q.from, 'kingo');
      expect(q.inChannel, 'general');
      expect(q.before, '2026-10-30');
      expect(q.after, '2026-10-01');
      expect(q.pinned, isTrue);
      expect(q.hasFilters, isTrue);
    });

    test('accepts the names without @ and #', () {
      final q = parseSearchQuery('from:bunx in:chill');
      expect(q.from, 'bunx');
      expect(q.inChannel, 'chill');
      expect(q.text, isEmpty);
    });

    test('leaves malformed filters and times in the text', () {
      final q = parseSearchQuery('meet at 10:30 before:tomorrow pinned:maybe');
      expect(q.text, 'meet at 10:30 before:tomorrow pinned:maybe');
      expect(q.hasFilters, isFalse);
    });

    test('a trailing colon is text', () {
      expect(parseSearchQuery('from:').text, 'from:');
    });
  });
}
