part of 'message_pane.dart';

/// The list item's key: the message id, distinct from the row's own
/// `ValueKey(id)` so lookups by that key still find exactly the row.
class MessageRowKey extends LocalKey {
  const MessageRowKey(this.messageId);

  final String messageId;

  @override
  bool operator ==(Object other) =>
      other is MessageRowKey && other.messageId == messageId;

  @override
  int get hashCode => Object.hash(MessageRowKey, messageId);

  @override
  String toString() => '[MessageRowKey $messageId]';
}

/// Wraps [row] with the dividers that go above it: a dated line when
/// [message] starts a new day (or the loaded history), and the red "NEW"
/// line when it is the first message after [unreadFrom]. The list's keyed
/// element is this wrapper, so the key moves here.
Widget withMessageDividers(
  Widget row, {
  required Key key,
  required AccordMessage? previous,
  required AccordMessage message,
  required String? unreadFrom,
}) {
  final day = parseServerTimestamp(message.timestamp)?.toLocal();
  final previousDay = previous == null
      ? null
      : parseServerTimestamp(previous.timestamp)?.toLocal();
  final newDay =
      day != null &&
      (previousDay == null ||
          day.year != previousDay.year ||
          day.month != previousDay.month ||
          day.day != previousDay.day);
  final firstUnread =
      unreadFrom != null &&
      compareMessageIds(message.id, unreadFrom) > 0 &&
      (previous == null || compareMessageIds(previous.id, unreadFrom) <= 0);
  if (!newDay && !firstUnread) return KeyedSubtree(key: key, child: row);
  return Column(
    key: key,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (newDay) _DayDivider(day: day),
      if (firstUnread) const _NewMessagesDivider(),
      row,
    ],
  );
}

const _kMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Today", "Yesterday" or "October 29, 2026".
String messageDayLabel(DateTime day, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(day.year, day.month, day.day);
  final t = DateTime(today.year, today.month, today.day);
  final delta = t.difference(d).inDays;
  if (delta == 0) return 'Today';
  if (delta == 1) return 'Yesterday';
  return '${_kMonths[day.month - 1]} ${day.day}, ${day.year}';
}

/// A thin rule with the date in the middle, between two days of history.
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final line = Expanded(child: Divider(color: colors.darkGray, height: 1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          line,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              messageDayLabel(day),
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: colors.gray,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}

/// The red "NEW" rule above the first message that arrived since the channel
/// was last read.
class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      key: const Key('new-messages-divider'),
      padding: const EdgeInsets.fromLTRB(16, 6, 0, 2),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: colors.red)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: colors.red,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(4),
              ),
            ),
            child: const Text(
              'NEW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
