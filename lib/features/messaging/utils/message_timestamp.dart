/// Dynamic timestamps in message text: `<t:UNIX>` or `<t:UNIX:STYLE>`, shown
/// in each reader's own time zone. Styles follow the common chat convention:
///
/// | Style | Example |
/// |---|---|
/// | `t` | 9:05 AM |
/// | `T` | 9:05:07 AM |
/// | `d` | 10/22/2026 |
/// | `D` | Oct 22, 2026 |
/// | `f` (default) | Oct 22, 2026 9:05 AM |
/// | `F` | Thursday, October 22, 2026 9:05 AM |
/// | `R` | in 3 hours / 2 days ago |
library;

/// `<t:SECONDS>` or `<t:SECONDS:STYLE>`.
final RegExp messageTimestampPattern = RegExp(
  r'<t:(-?\d{1,13})(?::([tTdDfFR]))?>',
);

/// The styles a timestamp token may name; anything else falls back to `f`.
const Set<String> messageTimestampStyles = {'t', 'T', 'd', 'D', 'f', 'F', 'R'};

/// The default style when the token names none.
const String defaultMessageTimestampStyle = 'f';

/// The instant a token's [seconds] denote, or null when out of range.
DateTime? messageTimestampInstant(String seconds) {
  final value = int.tryParse(seconds);
  if (value == null) return null;
  // DateTime supports ±8.64e15 ms; keep well inside it.
  if (value.abs() > 8640000000000) return null;
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
}

/// `in 3 hours` / `3 hours ago` / `in a few seconds` for [target] seen at [now].
String relativeTimeLabel(DateTime target, DateTime now) {
  final diff = target.difference(now);
  final future = !diff.isNegative;
  final seconds = diff.inSeconds.abs();
  String unit(int n, String one) => n == 1 ? 'a $one' : '$n ${one}s';
  final String amount;
  if (seconds < 45) {
    amount = 'a few seconds';
  } else if (seconds < 90) {
    amount = 'a minute';
  } else if (seconds < 45 * 60) {
    amount = unit((seconds / 60).round(), 'minute');
  } else if (seconds < 90 * 60) {
    amount = 'an hour';
  } else if (seconds < 22 * 3600) {
    amount = unit((seconds / 3600).round(), 'hour');
  } else if (seconds < 36 * 3600) {
    amount = 'a day';
  } else if (seconds < 26 * 86400) {
    amount = unit((seconds / 86400).round(), 'day');
  } else if (seconds < 45 * 86400) {
    amount = 'a month';
  } else if (seconds < 320 * 86400) {
    amount = unit((seconds / (30 * 86400)).round(), 'month');
  } else if (seconds < 548 * 86400) {
    amount = 'a year';
  } else {
    amount = unit((seconds / (365 * 86400)).round(), 'year');
  }
  return future ? 'in $amount' : '$amount ago';
}

/// How often a relative timestamp should refresh: every few seconds while it's
/// close, less often further out.
Duration relativeTimeRefresh(DateTime target, DateTime now) {
  final distance = target.difference(now).abs();
  if (distance < const Duration(minutes: 1)) return const Duration(seconds: 5);
  if (distance < const Duration(hours: 1)) return const Duration(seconds: 30);
  return const Duration(minutes: 5);
}
