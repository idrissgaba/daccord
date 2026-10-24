import '../utils/json_utils.dart';

/// A space's sticker (or, inside a message, the sticker it carries).
class AccordSticker {
  AccordSticker({
    required this.id,
    required this.name,
    this.spaceId,
    this.description,
    this.tags,
    this.image,
    this.format = 'png',
  });

  final String id;
  final String name;
  final String? spaceId;
  final String? description;

  /// An emoji the sticker relates to.
  final String? tags;

  /// CDN path of the image; null for a sticker deleted since it was sent.
  final String? image;

  /// `png`, `gif` or `webp`.
  final String format;

  factory AccordSticker.fromJson(Map<String, dynamic> d) => AccordSticker(
        id: asString(d['id']),
        name: asString(d['name']),
        spaceId: asStringOrNull(d['space_id']),
        description: asStringOrNull(d['description']),
        tags: asStringOrNull(d['tags']),
        image: asStringOrNull(d['image']),
        format: asString(d['format'], 'png'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (spaceId != null) 'space_id': spaceId,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
        'image': image,
        'format': format,
      };
}
