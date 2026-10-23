/// Pure helpers for scheduled events, kept out of the widgets so they can be
/// unit-tested.
library;

import 'package:accordkit/accordkit.dart';

/// Whether [event] still belongs in the list (coming up or under way).
bool eventIsOpen(AccordScheduledEvent event) =>
    event.status == 'scheduled' || event.status == 'active';

/// Events under way first, then the rest soonest first.
List<AccordScheduledEvent> sortEvents(Iterable<AccordScheduledEvent> events) =>
    events.where(eventIsOpen).toList()..sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.startTime.compareTo(b.startTime);
    });

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// `20:30`, in local time.
String eventClock(DateTime time) {
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// When an event happens, for its card: `Live now`, `Today at 20:30`,
/// `Tomorrow at 20:30`, `Sat 1 Nov at 20:30` (local time, relative to
/// [now]).
String eventWhenLabel(AccordScheduledEvent event, DateTime now) {
  if (event.isActive) return 'Live now';
  final start = event.start?.toLocal();
  if (start == null) return '';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(start.year, start.month, start.day);
  final days = day.difference(today).inDays;
  final clock = eventClock(start);
  if (days == 0) return 'Today at $clock';
  if (days == 1) return 'Tomorrow at $clock';
  return '${_weekdays[start.weekday - 1]} ${start.day} '
      '${_months[start.month - 1]} at $clock';
}

/// The request body for an event's fields.
Map<String, dynamic> eventPayload({
  required String name,
  required String description,
  required bool voice,
  String? channelId,
  String? location,
  required DateTime start,
  DateTime? end,
}) => {
  'name': name.trim(),
  'description': description.trim(),
  'entity_type': voice ? 'voice' : 'external',
  if (voice) 'channel_id': channelId,
  if (!voice) 'location': location?.trim(),
  'start_time': start.toUtc().toIso8601String(),
  if (end != null) 'end_time': end.toUtc().toIso8601String(),
};

/// What's wrong with an event form, or null (mirrors the server's rules).
String? eventFormError({
  required String name,
  required bool voice,
  String? channelId,
  String? location,
  required DateTime start,
  DateTime? end,
  required DateTime now,
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || trimmed.length > 100) {
    return 'Give the event a name (up to 100 characters).';
  }
  if (voice && (channelId == null || channelId.isEmpty)) {
    return 'Pick the voice channel it happens in.';
  }
  if (!voice && (location == null || location.trim().isEmpty)) {
    return 'Say where it happens.';
  }
  if (!voice && end == null) {
    return 'An event somewhere else needs an end time.';
  }
  if (start.isBefore(now.subtract(const Duration(minutes: 5)))) {
    return 'The start time has passed.';
  }
  if (end != null && !end.isAfter(start)) return 'It must end after it starts.';
  return null;
}

String _icsTime(DateTime time) {
  final t = time.toUtc();
  return '${t.year}${_two(t.month)}${_two(t.day)}T'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
}

String _icsText(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n');

/// An iCalendar file (RFC 5545) for adding [event] to a calendar. Without an
/// end, it lasts an hour.
String buildIcs(
  AccordScheduledEvent event, {
  required String where,
  required DateTime now,
}) {
  final start = event.start ?? now;
  final end = event.end ?? start.add(const Duration(hours: 1));
  final lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//daccord//events//EN',
    'BEGIN:VEVENT',
    'UID:event-${event.id}@daccord',
    'DTSTAMP:${_icsTime(now)}',
    'DTSTART:${_icsTime(start)}',
    'DTEND:${_icsTime(end)}',
    'SUMMARY:${_icsText(event.name)}',
    if (event.description != null && event.description!.isNotEmpty)
      'DESCRIPTION:${_icsText(event.description!)}',
    if (where.isNotEmpty) 'LOCATION:${_icsText(where)}',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  return '${lines.join('\r\n')}\r\n';
}

/// A file name for [event]'s calendar file.
String icsFileName(AccordScheduledEvent event) {
  final slug = event.name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${slug.isEmpty ? 'event' : slug}.ics';
}
