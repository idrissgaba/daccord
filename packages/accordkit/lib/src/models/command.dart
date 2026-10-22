import '../utils/json_utils.dart';

/// A fixed choice of a slash command option.
class AccordCommandChoice {
  AccordCommandChoice({required this.name, this.value});

  final String name;
  final Object? value;

  factory AccordCommandChoice.fromJson(Map<String, dynamic> d) =>
      AccordCommandChoice(name: asString(d['name']), value: d['value']);

  Map<String, dynamic> toJson() => {'name': name, 'value': value};
}

/// One option of a slash command. [type] is `string`, `integer`, `number`,
/// `boolean`, `user`, `channel` or `role`.
class AccordCommandOption {
  AccordCommandOption({
    required this.name,
    required this.description,
    required this.type,
    this.required = false,
    this.choices = const [],
    this.minValue,
    this.maxValue,
    this.minLength,
    this.maxLength,
  });

  final String name;
  final String description;
  final String type;
  final bool required;
  final List<AccordCommandChoice> choices;
  final num? minValue;
  final num? maxValue;
  final int? minLength;
  final int? maxLength;

  factory AccordCommandOption.fromJson(Map<String, dynamic> d) =>
      AccordCommandOption(
        name: asString(d['name']),
        description: asString(d['description']),
        type: asString(d['type'], 'string'),
        required: asBool(d['required']),
        choices: [
          for (final c in asList(d['choices']) ?? const [])
            if (asMap(c) != null) AccordCommandChoice.fromJson(asMap(c)!),
        ],
        minValue: d['min_value'] is num ? d['min_value'] as num : null,
        maxValue: d['max_value'] is num ? d['max_value'] as num : null,
        minLength: d['min_length'] is int ? d['min_length'] as int : null,
        maxLength: d['max_length'] is int ? d['max_length'] as int : null,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'type': type,
        'required': required,
        if (choices.isNotEmpty)
          'choices': [for (final c in choices) c.toJson()],
        if (minValue != null) 'min_value': minValue,
        if (maxValue != null) 'max_value': maxValue,
        if (minLength != null) 'min_length': minLength,
        if (maxLength != null) 'max_length': maxLength,
      };
}

/// A slash command an application offers in a space.
class AccordCommand {
  AccordCommand({
    required this.id,
    required this.applicationId,
    required this.name,
    required this.description,
    this.options = const [],
    this.applicationName = '',
    this.botUserId,
  });

  final String id;
  final String applicationId;
  final String name;
  final String description;
  final List<AccordCommandOption> options;
  final String applicationName;

  /// The bot that answers it.
  final String? botUserId;

  factory AccordCommand.fromJson(Map<String, dynamic> d) {
    final app = asMap(d['application']);
    return AccordCommand(
      id: asString(d['id']),
      applicationId: asString(d['application_id']),
      name: asString(d['name']),
      description: asString(d['description']),
      options: [
        for (final o in asList(d['options']) ?? const [])
          if (asMap(o) != null) AccordCommandOption.fromJson(asMap(o)!),
      ],
      applicationName: asString(app?['name']),
      botUserId: asStringOrNull(app?['bot_user_id']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'application_id': applicationId,
        'name': name,
        'description': description,
        'options': [for (final o in options) o.toJson()],
        'application': {'name': applicationName, 'bot_user_id': botUserId},
      };
}

/// The command a bot's message answers (`interaction` in message JSON).
class AccordMessageInteraction {
  AccordMessageInteraction({
    required this.id,
    required this.type,
    required this.userId,
    this.name,
  });

  final String id;

  /// `application_command` or `message_component`.
  final String type;
  final String? name;

  /// Who used the command.
  final String userId;

  factory AccordMessageInteraction.fromJson(Map<String, dynamic> d) =>
      AccordMessageInteraction(
        id: asString(d['id']),
        type: asString(d['type']),
        name: asStringOrNull(d['name']),
        userId: asString(d['user_id']),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'type': type, 'name': name, 'user_id': userId};
}
