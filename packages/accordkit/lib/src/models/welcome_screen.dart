import '../utils/json_utils.dart';

/// One recommended channel of a welcome screen.
class AccordWelcomeChannel {
  AccordWelcomeChannel({
    required this.channelId,
    required this.description,
    this.emoji,
  });

  final String channelId;
  final String description;
  final String? emoji;

  factory AccordWelcomeChannel.fromJson(Map<String, dynamic> d) =>
      AccordWelcomeChannel(
        channelId: asString(d['channel_id']),
        description: asString(d['description']),
        emoji: asStringOrNull(d['emoji']),
      );

  Map<String, dynamic> toJson() => {
        'channel_id': channelId,
        'description': description,
        if (emoji != null) 'emoji': emoji,
      };
}

/// A space's welcome screen, shown to members on their first visit.
class AccordWelcomeScreen {
  AccordWelcomeScreen({
    this.enabled = false,
    this.description,
    this.channels = const [],
  });

  final bool enabled;
  final String? description;
  final List<AccordWelcomeChannel> channels;

  factory AccordWelcomeScreen.fromJson(Map<String, dynamic> d) =>
      AccordWelcomeScreen(
        enabled: asBool(d['enabled']),
        description: asStringOrNull(d['description']),
        channels: [
          for (final c in asList(d['channels']) ?? const [])
            if (asMap(c) != null) AccordWelcomeChannel.fromJson(asMap(c)!),
        ],
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'description': description,
        'channels': [for (final c in channels) c.toJson()],
      };
}
