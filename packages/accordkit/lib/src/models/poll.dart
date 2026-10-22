import '../utils/json_utils.dart';

/// One answer of an [AccordPoll].
class AccordPollAnswer {
  AccordPollAnswer({
    required this.answerId,
    required this.text,
    this.emoji,
    this.votes = 0,
    this.me,
  });

  final int answerId;
  final String text;
  final String? emoji;
  int votes;

  /// Whether the signed-in user picked this answer; null when the payload
  /// didn't say (gateway broadcasts carry counts only).
  bool? me;

  factory AccordPollAnswer.fromJson(Map<String, dynamic> d) => AccordPollAnswer(
        answerId: asInt(d['answer_id']),
        text: asString(d['text']),
        emoji: asStringOrNull(d['emoji']),
        votes: asInt(d['votes']),
        me: d['me'] is bool ? d['me'] as bool : null,
      );

  Map<String, dynamic> toJson() => {
        'answer_id': answerId,
        'text': text,
        'emoji': emoji,
        'votes': votes,
        if (me != null) 'me': me,
      };
}

/// A poll attached to a message (`poll` in message JSON).
class AccordPoll {
  AccordPoll({
    required this.question,
    required this.answers,
    this.allowMultiselect = false,
    this.expiresAt,
    this.closed = false,
    this.totalVotes = 0,
  });

  final String question;
  final List<AccordPollAnswer> answers;
  final bool allowMultiselect;
  final String? expiresAt;
  bool closed;
  int totalVotes;

  /// Whether this copy says which answers the signed-in user picked.
  bool get knowsMine => answers.any((a) => a.me != null);

  /// Whether the signed-in user has voted (as far as this copy knows).
  bool get hasMyVote => answers.any((a) => a.me == true);

  /// When a broadcast carries counts only, keep the user's own picks from the
  /// copy already shown.
  void adoptMineFrom(AccordPoll previous) {
    if (knowsMine) return;
    for (final answer in answers) {
      for (final old in previous.answers) {
        if (old.answerId == answer.answerId) answer.me = old.me;
      }
    }
  }

  factory AccordPoll.fromJson(Map<String, dynamic> d) => AccordPoll(
        question: asString(d['question']),
        answers: [
          for (final a in asList(d['answers']) ?? const [])
            if (asMap(a) != null) AccordPollAnswer.fromJson(asMap(a)!),
        ],
        allowMultiselect: asBool(d['allow_multiselect']),
        expiresAt: asStringOrNull(d['expires_at']),
        closed: asBool(d['closed']),
        totalVotes: asInt(d['total_votes']),
      );

  Map<String, dynamic> toJson() => {
        'question': question,
        'answers': [for (final a in answers) a.toJson()],
        'allow_multiselect': allowMultiselect,
        'expires_at': expiresAt,
        'closed': closed,
        'total_votes': totalVotes,
      };
}
