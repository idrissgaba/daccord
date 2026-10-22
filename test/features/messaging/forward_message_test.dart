import 'package:bonfire/features/messaging/utils/forward_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('quotes the original under a Forwarded line with a jump link', () {
    final text = forwardedMessageContent(
      original: 'first\nsecond',
      authorName: 'Idris',
      sourceLabel: '#general',
      link: 'daccord://navigate/1/2?msg=3',
    );
    expect(
      text,
      '-# ↪ Forwarded from #general · Idris · '
      '[Jump to original](daccord://navigate/1/2?msg=3)\n'
      '> first\n'
      '> second',
    );
  });

  test('puts the comment first', () {
    final text = forwardedMessageContent(
      original: 'hello',
      authorName: 'A',
      sourceLabel: 'a direct message',
      comment: '  look at this ',
    );
    expect(
      text,
      startsWith('look at this\n\n-# ↪ Forwarded from a direct message · A'),
    );
    expect(text, endsWith('> hello'));
  });

  test('a file-only message forwards just the header', () {
    final text = forwardedMessageContent(
      original: '   ',
      authorName: 'A',
      sourceLabel: '#media',
    );
    expect(text, '-# ↪ Forwarded from #media · A');
  });

  test('a long original is shortened to the length limit', () {
    final text = forwardedMessageContent(
      original: 'x' * 5000,
      authorName: 'A',
      sourceLabel: '#general',
    );
    expect(text.length, lessThanOrEqualTo(maxForwardedMessageLength));
    expect(text, endsWith('…'));
  });
}
