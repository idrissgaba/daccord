/// Pure helpers for slash commands and message components, kept out of the
/// widgets so they can be unit-tested.
library;

import 'package:accordkit/accordkit.dart';

/// Message flag: only the member who used the command sees the message.
const int messageFlagEphemeral = 1 << 6;

/// Message flag: the application is still preparing its answer.
const int messageFlagLoading = 1 << 7;

bool isEphemeralMessage(AccordMessage message) =>
    message.flags & messageFlagEphemeral != 0;

bool isLoadingMessage(AccordMessage message) =>
    message.flags & messageFlagLoading != 0;

/// How long an application has to acknowledge before the interaction counts
/// as failed.
const Duration interactionTimeout = Duration(seconds: 5);

/// The command name being typed when [text] is `/` followed by a name and
/// nothing else yet (`/pl` → `pl`); null otherwise.
String? slashQuery(String text) {
  if (!text.startsWith('/')) return null;
  final rest = text.substring(1);
  if (rest.contains(RegExp(r'\s'))) return null;
  return rest.toLowerCase();
}

/// The commands matching [query]: names starting with it first, then (from
/// two letters on) names containing it, each group in the order given; at
/// most [limit].
List<AccordCommand> matchCommands(
  Iterable<AccordCommand> commands,
  String query, {
  int limit = 8,
}) {
  final q = query.toLowerCase();
  final starts = <AccordCommand>[];
  final contains = <AccordCommand>[];
  for (final command in commands) {
    final name = command.name.toLowerCase();
    if (name.startsWith(q)) {
      starts.add(command);
    } else if (q.length >= 2 && name.contains(q)) {
      contains.add(command);
    }
  }
  return [...starts, ...contains].take(limit).toList();
}

/// A typed `/name rest of the line`, resolved without the options form: the
/// command [name] matches exactly and either takes no option or [rest] fills
/// its first option, a text one, and no other is required. Null when the
/// form is needed (or nothing matches).
({AccordCommand command, List<Map<String, dynamic>> options})?
parseQuickCommand(String text, Iterable<AccordCommand> commands) {
  final match = RegExp(r'^/(\S+)(?:\s+([\s\S]*))?$').firstMatch(text.trim());
  if (match == null) return null;
  final name = match.group(1)!.toLowerCase();
  final rest = (match.group(2) ?? '').trim();
  final candidates = commands.where((c) => c.name == name).toList();
  if (candidates.length != 1) return null;
  final command = candidates.single;
  final options = command.options;
  if (rest.isEmpty) {
    if (options.any((o) => o.required)) return null;
    return (command: command, options: const []);
  }
  if (options.isEmpty ||
      options.first.type != 'string' ||
      options.first.choices.isNotEmpty ||
      options.skip(1).any((o) => o.required)) {
    return null;
  }
  return (
    command: command,
    options: [
      {'name': options.first.name, 'value': rest},
    ],
  );
}

/// [raw] (what was typed or picked for [option]) as the value to send, or
/// the reason it can't be. An empty optional value is `(value: null)`.
({Object? value, String? error}) optionValue(
  AccordCommandOption option,
  Object? raw,
) {
  if (raw == null || (raw is String && raw.trim().isEmpty)) {
    return option.required
        ? (value: null, error: '${option.name} is required')
        : (value: null, error: null);
  }
  if (option.choices.isNotEmpty) {
    final allowed = option.choices.any((c) => c.value == raw);
    return allowed
        ? (value: raw, error: null)
        : (value: null, error: 'Pick one of the choices for ${option.name}');
  }
  switch (option.type) {
    case 'integer':
      final number = raw is int ? raw : int.tryParse('$raw'.trim());
      if (number == null) {
        return (value: null, error: '${option.name} must be a whole number');
      }
      return _inRange(option, number);
    case 'number':
      final number = raw is num ? raw : num.tryParse('$raw'.trim());
      if (number == null) {
        return (value: null, error: '${option.name} must be a number');
      }
      return _inRange(option, number);
    case 'boolean':
      if (raw is bool) return (value: raw, error: null);
      return (value: null, error: '${option.name} must be on or off');
    case 'string':
      final text = '$raw'.trim();
      if (option.minLength != null && text.length < option.minLength!) {
        return (
          value: null,
          error: '${option.name} needs at least ${option.minLength} characters',
        );
      }
      if (option.maxLength != null && text.length > option.maxLength!) {
        return (
          value: null,
          error: '${option.name} takes at most ${option.maxLength} characters',
        );
      }
      return (value: text, error: null);
    default: // user, channel, role: an id picked from a list
      return (value: '$raw', error: null);
  }
}

({Object? value, String? error}) _inRange(
  AccordCommandOption option,
  num number,
) {
  if ((option.minValue != null && number < option.minValue!) ||
      (option.maxValue != null && number > option.maxValue!)) {
    final min = option.minValue;
    final max = option.maxValue;
    final range = min != null && max != null
        ? 'between $min and $max'
        : min != null
        ? 'at least $min'
        : 'at most $max';
    return (value: null, error: '${option.name} must be $range');
  }
  return (value: number, error: null);
}

/// The `{name, value}` options to send for a filled-in form, or the first
/// problem with it.
({List<Map<String, dynamic>> options, String? error}) collectOptions(
  AccordCommand command,
  Map<String, Object?> raw,
) {
  final options = <Map<String, dynamic>>[];
  for (final option in command.options) {
    final checked = optionValue(option, raw[option.name]);
    if (checked.error != null) return (options: const [], error: checked.error);
    if (checked.value != null) {
      options.add({'name': option.name, 'value': checked.value});
    }
  }
  return (options: options, error: null);
}

/// A button's look.
enum ComponentButtonStyle { primary, secondary, success, danger, link }

sealed class MessageComponent {
  const MessageComponent();
}

class ComponentButton extends MessageComponent {
  const ComponentButton({
    required this.style,
    required this.label,
    this.emoji,
    this.customId,
    this.url,
    this.disabled = false,
  });

  final ComponentButtonStyle style;
  final String label;

  /// A unicode emoji (custom emoji show their name).
  final String? emoji;
  final String? customId;
  final String? url;
  final bool disabled;
}

class ComponentSelectOption {
  const ComponentSelectOption({
    required this.label,
    required this.value,
    this.description,
    this.emoji,
    this.isDefault = false,
  });

  final String label;
  final String value;
  final String? description;
  final String? emoji;
  final bool isDefault;
}

class ComponentSelect extends MessageComponent {
  const ComponentSelect({
    required this.customId,
    required this.options,
    this.placeholder,
    this.minValues = 1,
    this.maxValues = 1,
    this.disabled = false,
  });

  final String customId;
  final List<ComponentSelectOption> options;
  final String? placeholder;
  final int minValues;
  final int maxValues;
  final bool disabled;
}

String? _emojiText(Object? raw) {
  if (raw is String && raw.isNotEmpty) return raw;
  if (raw is Map) {
    final name = raw['name'];
    if (name is String && name.isNotEmpty) return name;
  }
  return null;
}

ComponentButtonStyle _buttonStyle(Object? raw) => switch (raw) {
  'primary' || 1 => ComponentButtonStyle.primary,
  'success' || 3 => ComponentButtonStyle.success,
  'danger' || 4 => ComponentButtonStyle.danger,
  'link' || 5 => ComponentButtonStyle.link,
  _ => ComponentButtonStyle.secondary,
};

/// The rows of components in a message's `components` JSON. Anything
/// malformed is skipped rather than failing the message.
List<List<MessageComponent>> parseComponents(Object? raw) {
  if (raw is! List) return const [];
  final rows = <List<MessageComponent>>[];
  for (final row in raw) {
    if (row is! Map || row['components'] is! List) continue;
    final items = <MessageComponent>[];
    for (final item in row['components'] as List) {
      if (item is! Map) continue;
      final type = item['type'];
      if (type == 'button' || type == 2) {
        final style = _buttonStyle(item['style']);
        final label = item['label'] is String ? item['label'] as String : '';
        final customId = item['custom_id'] is String
            ? item['custom_id'] as String
            : null;
        final url = item['url'] is String ? item['url'] as String : null;
        if (style == ComponentButtonStyle.link
            ? url == null
            : customId == null) {
          continue;
        }
        items.add(
          ComponentButton(
            style: style,
            label: label,
            emoji: _emojiText(item['emoji']),
            customId: customId,
            url: url,
            disabled: item['disabled'] == true,
          ),
        );
      } else if (type == 'select' || type == 3) {
        final customId = item['custom_id'];
        final options = [
          for (final option in (item['options'] as List?) ?? const [])
            if (option is Map &&
                option['label'] is String &&
                option['value'] is String)
              ComponentSelectOption(
                label: option['label'] as String,
                value: option['value'] as String,
                description: option['description'] is String
                    ? option['description'] as String
                    : null,
                emoji: _emojiText(option['emoji']),
                isDefault: option['default'] == true,
              ),
        ];
        if (customId is! String || options.isEmpty) continue;
        items.add(
          ComponentSelect(
            customId: customId,
            options: options,
            placeholder: item['placeholder'] is String
                ? item['placeholder'] as String
                : null,
            minValues: item['min_values'] is int
                ? item['min_values'] as int
                : 1,
            maxValues: item['max_values'] is int
                ? item['max_values'] as int
                : 1,
            disabled: item['disabled'] == true,
          ),
        );
      }
    }
    if (items.isNotEmpty) rows.add(items);
  }
  return rows;
}
