/// Display helpers for polls, kept pure so they can be unit-tested.
library;

/// Durations offered when creating a poll, in hours.
const List<int> pollDurationOptions = [1, 4, 8, 24, 72, 168, 336];

/// Most answers a poll may have (the server's limit).
const int maxPollAnswers = 10;

/// Longest question and answer, in characters (the server's limits).
const int maxPollQuestionLength = 300;
const int maxPollAnswerLength = 55;

/// `1 hour`, `3 days`, `1 week`… for the duration picker.
String pollDurationLabel(int hours) {
  if (hours % 168 == 0) {
    final weeks = hours ~/ 168;
    return weeks == 1 ? '1 week' : '$weeks weeks';
  }
  if (hours % 24 == 0) {
    final days = hours ~/ 24;
    return days == 1 ? '1 day' : '$days days';
  }
  return hours == 1 ? '1 hour' : '$hours hours';
}

/// The share of [votes] in [total], as a whole percentage.
int pollPercent(int votes, int total) =>
    total <= 0 ? 0 : (votes * 100 / total).round();

/// `ends in 3h` / `ends in 2d` / `ends in 45m` / `ends soon`.
String pollTimeLeft(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  if (left.inMinutes < 1) return 'ends soon';
  if (left.inHours < 1) return 'ends in ${left.inMinutes}m';
  if (left.inDays < 1) return 'ends in ${left.inHours}h';
  return 'ends in ${left.inDays}d';
}

/// The line under a poll: vote count and time left (or that it closed).
String pollFooter({
  required int totalVotes,
  required bool closed,
  DateTime? expiresAt,
  required DateTime now,
}) {
  final votes = totalVotes == 1 ? '1 vote' : '$totalVotes votes';
  if (closed || (expiresAt != null && !expiresAt.isAfter(now))) {
    return '$votes · Poll closed';
  }
  if (expiresAt == null) return votes;
  return '$votes · ${pollTimeLeft(expiresAt, now)}';
}
