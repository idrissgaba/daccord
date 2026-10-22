import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/utils/poll_display.dart';
import 'package:bonfire/features/messaging/views/poll_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _pollJson({
  bool? meFirst,
  bool closed = false,
  bool multi = false,
  String? expires,
}) => {
  'question': 'Pizza or sushi?',
  'answers': [
    {
      'answer_id': 1,
      'text': 'Pizza',
      'votes': 3,
      if (meFirst != null) 'me': meFirst,
    },
    {
      'answer_id': 2,
      'text': 'Sushi',
      'emoji': '🍣',
      'votes': 1,
      if (meFirst != null) 'me': false,
    },
  ],
  'allow_multiselect': multi,
  'expires_at':
      expires ??
      DateTime.now().toUtc().add(const Duration(hours: 3)).toIso8601String(),
  'closed': closed,
  'total_votes': 4,
};

Widget _host(Widget child) => MaterialApp(
  theme: buildAppTheme(AppThemePreset.dark),
  home: Scaffold(body: child),
);

void main() {
  group('poll display helpers', () {
    test('durations read naturally', () {
      expect(pollDurationLabel(1), '1 hour');
      expect(pollDurationLabel(8), '8 hours');
      expect(pollDurationLabel(24), '1 day');
      expect(pollDurationLabel(72), '3 days');
      expect(pollDurationLabel(168), '1 week');
      expect(pollDurationLabel(336), '2 weeks');
    });

    test('percentages round and survive zero votes', () {
      expect(pollPercent(1, 3), 33);
      expect(pollPercent(2, 3), 67);
      expect(pollPercent(0, 0), 0);
    });

    test('footer shows votes and time left, or closed', () {
      final now = DateTime.utc(2026, 10, 22, 12);
      expect(
        pollFooter(
          totalVotes: 1,
          closed: false,
          expiresAt: now.add(const Duration(hours: 5)),
          now: now,
        ),
        '1 vote · ends in 5h',
      );
      expect(
        pollFooter(
          totalVotes: 4,
          closed: false,
          expiresAt: now.add(const Duration(days: 2, hours: 1)),
          now: now,
        ),
        '4 votes · ends in 2d',
      );
      expect(
        pollFooter(
          totalVotes: 4,
          closed: false,
          expiresAt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        '4 votes · Poll closed',
      );
      expect(
        pollFooter(totalVotes: 0, closed: true, expiresAt: null, now: now),
        '0 votes · Poll closed',
      );
    });

    test('blank answers are dropped', () {
      expect(filledPollAnswers([' a ', '', '  ', 'b']), ['a', 'b']);
    });
  });

  group('AccordPoll', () {
    test('parses and serialises', () {
      final poll = AccordPoll.fromJson(_pollJson(meFirst: true));
      expect(poll.question, 'Pizza or sushi?');
      expect(poll.answers.map((a) => a.votes), [3, 1]);
      expect(poll.answers[1].emoji, '🍣');
      expect(poll.hasMyVote, isTrue);
      final again = AccordPoll.fromJson(poll.toJson());
      expect(again.answers.first.me, isTrue);
      expect(again.totalVotes, 4);
    });

    test('a message carries its poll', () {
      final message = AccordMessage.fromJson({
        'id': '1',
        'channel_id': 'c',
        'author_id': 'u',
        'content': '',
        'poll': _pollJson(),
      });
      expect(message.poll?.question, 'Pizza or sushi?');
      expect(message.toJson()['poll'], isNotNull);
    });
  });

  test('an update keeps known reactions and my poll picks', () {
    final previous = AccordMessage.fromJson({
      'id': '1',
      'channel_id': 'c',
      'author_id': 'u',
      'content': '',
      'reactions': [
        {
          'emoji': {'name': '👍'},
          'count': 2,
          'me': true,
        },
      ],
      'poll': _pollJson(meFirst: true),
    });
    final broadcast = AccordMessage.fromJson({
      'id': '1',
      'channel_id': 'c',
      'author_id': 'u',
      'content': '',
      'poll': _pollJson(),
    });
    keepViewerState(broadcast, previous);
    expect(broadcast.reactions, hasLength(1));
    expect(broadcast.poll!.answers.first.me, isTrue);
    expect(broadcast.poll!.answers.last.me, isFalse);
  });

  group('PollView', () {
    testWidgets('voting calls back, and a picked answer withdraws', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpWidget(
        _host(
          PollView(
            poll: AccordPoll.fromJson(_pollJson(meFirst: true)),
            onVote: (answerId, {required remove}) async {
              calls.add('$answerId:$remove');
              return null;
            },
          ),
        ),
      );
      expect(find.text('Pizza or sushi?'), findsOneWidget);
      // Voted already, so the results show.
      expect(find.text('75% (3)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('poll-answer-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('poll-answer-1')));
      await tester.pump();
      expect(calls, ['2:false', '1:true']);
    });

    testWidgets('results stay hidden before voting', (tester) async {
      await tester.pumpWidget(
        _host(
          PollView(
            poll: AccordPoll.fromJson(_pollJson(meFirst: false)),
            onVote: (answerId, {required remove}) async => null,
          ),
        ),
      );
      expect(find.text('75% (3)'), findsNothing);
      expect(find.text('Select one answer'), findsOneWidget);
    });

    testWidgets('a closed poll shows results and ignores taps', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _host(
          PollView(
            poll: AccordPoll.fromJson(_pollJson(closed: true)),
            onVote: (answerId, {required remove}) async {
              tapped = true;
              return null;
            },
          ),
        ),
      );
      expect(find.text('75% (3)'), findsOneWidget);
      expect(find.textContaining('Poll closed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('poll-answer-1')));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('a failed vote shows the reason', (tester) async {
      await tester.pumpWidget(
        _host(
          PollView(
            poll: AccordPoll.fromJson(_pollJson(meFirst: false)),
            onVote: (answerId, {required remove}) async =>
                'this poll has ended',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('poll-answer-1')));
      await tester.pump();
      expect(find.text('this poll has ended'), findsOneWidget);
    });
  });
}
