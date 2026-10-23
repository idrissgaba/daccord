import '../utils/json_utils.dart';

/// A space's scheduled event, in a voice channel ([entityType] `voice`) or
/// somewhere else (`external`, with a [location]).
class AccordScheduledEvent {
  AccordScheduledEvent({
    required this.id,
    required this.spaceId,
    required this.name,
    required this.entityType,
    required this.status,
    required this.startTime,
    this.channelId,
    this.creatorId,
    this.description,
    this.location,
    this.endTime,
    this.image,
    this.userCount = 0,
    this.interested,
  });

  final String id;
  final String spaceId;
  final String name;

  /// `voice` or `external`.
  final String entityType;

  /// `scheduled`, `active`, `completed` or `canceled`.
  final String status;

  /// RFC 3339, UTC.
  final String startTime;
  final String? endTime;
  final String? channelId;
  final String? creatorId;
  final String? description;
  final String? location;

  /// CDN path of the cover image.
  final String? image;
  final int userCount;

  /// Whether the signed-in member is interested; null when the payload
  /// (a gateway broadcast) doesn't say.
  final bool? interested;

  bool get isActive => status == 'active';
  bool get isVoice => entityType == 'voice';

  DateTime? get start => DateTime.tryParse(startTime);
  DateTime? get end => endTime == null ? null : DateTime.tryParse(endTime!);

  AccordScheduledEvent copyWith({int? userCount, bool? interested}) =>
      AccordScheduledEvent(
        id: id,
        spaceId: spaceId,
        name: name,
        entityType: entityType,
        status: status,
        startTime: startTime,
        channelId: channelId,
        creatorId: creatorId,
        description: description,
        location: location,
        endTime: endTime,
        image: image,
        userCount: userCount ?? this.userCount,
        interested: interested ?? this.interested,
      );

  factory AccordScheduledEvent.fromJson(Map<String, dynamic> d) =>
      AccordScheduledEvent(
        id: asString(d['id']),
        spaceId: asString(d['space_id']),
        name: asString(d['name']),
        entityType: asString(d['entity_type'], 'voice'),
        status: asString(d['status'], 'scheduled'),
        startTime: asString(d['start_time']),
        endTime: asStringOrNull(d['end_time']),
        channelId: asStringOrNull(d['channel_id']),
        creatorId: asStringOrNull(d['creator_id']),
        description: asStringOrNull(d['description']),
        location: asStringOrNull(d['location']),
        image: asStringOrNull(d['image']),
        userCount: asInt(d['user_count']),
        interested: d['interested'] is bool ? d['interested'] as bool : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'space_id': spaceId,
        'name': name,
        'entity_type': entityType,
        'status': status,
        'start_time': startTime,
        'end_time': endTime,
        'channel_id': channelId,
        'creator_id': creatorId,
        'description': description,
        'location': location,
        'image': image,
        'user_count': userCount,
        if (interested != null) 'interested': interested,
      };
}
