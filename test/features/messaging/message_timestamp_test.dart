import 'package:bonfire/features/messaging/utils/message_timestamp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 22, 12);

  group('messageTimestampPattern', () {
    test('matches the bare and styled forms', () {
      final bare = messageTimestampPattern.firstMatch('<t:1792660000>');
      expect(bare?[1], '1792660000');
      expect(bare?[2], isNull);
      final styled = messageTimestampPattern.firstMatch('<t:1792660000:R>');
      expect(styled?[2], 'R');
    });

    test('rejects unknown styles and non-numbers', () {
      expect(messageTimestampPattern.hasMatch('<t:1792660000:x>'), isFalse);
      expect(messageTimestampPattern.hasMatch('<t:abc>'), isFalse);
    });
  });

  test(
    'messageTimestampInstant converts seconds and refuses absurd values',
    () {
      expect(
        messageTimestampInstant('0'),
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(messageTimestampInstant('9999999999999'), isNull);
    },
  );

  group('relativeTimeLabel', () {
    test('near times read as a few seconds', () {
      expect(
        relativeTimeLabel(now.add(const Duration(seconds: 10)), now),
        'in a few seconds',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(seconds: 10)), now),
        'a few seconds ago',
      );
    });

    test('rounds into the next unit', () {
      expect(
        relativeTimeLabel(now.add(const Duration(minutes: 5)), now),
        'in 5 minutes',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(hours: 3)), now),
        '3 hours ago',
      );
      expect(
        relativeTimeLabel(now.add(const Duration(days: 1)), now),
        'in a day',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 10)), now),
        '10 days ago',
      );
      expect(
        relativeTimeLabel(now.add(const Duration(days: 90)), now),
        'in 3 months',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 800)), now),
        '2 years ago',
      );
    });
  });

  test('relative timestamps refresh faster when close', () {
    expect(
      relativeTimeRefresh(now.add(const Duration(seconds: 20)), now),
      const Duration(seconds: 5),
    );
    expect(
      relativeTimeRefresh(now.add(const Duration(minutes: 20)), now),
      const Duration(seconds: 30),
    );
    expect(
      relativeTimeRefresh(now.add(const Duration(days: 2)), now),
      const Duration(minutes: 5),
    );
  });
}
