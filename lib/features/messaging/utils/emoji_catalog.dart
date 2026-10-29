import 'package:flutter/material.dart';

part 'emoji_catalog_data.dart';

/// Standard unicode emoji categories shown in the picker (custom space emoji
/// and recently-used are handled separately by the picker UI).
enum EmojiCategory {
  smileys('Smileys', Icons.emoji_emotions_outlined),
  people('People', Icons.emoji_people_outlined),
  nature('Nature', Icons.pets_outlined),
  food('Food', Icons.restaurant_outlined),
  activities('Activities', Icons.sports_esports_outlined),
  travel('Travel', Icons.directions_car_filled_outlined),
  objects('Objects', Icons.lightbulb_outline),
  symbols('Symbols', Icons.emoji_symbols_outlined),
  flags('Flags', Icons.flag_outlined);

  const EmojiCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A single built-in unicode emoji and its searchable name.
class EmojiEntry {
  const EmojiEntry(
    this.char,
    this.name,
    this.category, [
    this.keywords = '',
    this.tones,
  ]);

  /// The unicode character (what gets inserted / reacted with).
  final String char;

  /// Canonical short name (e.g. `joy`), also used as the search key.
  final String name;

  final EmojiCategory category;

  /// Extra space-separated search terms.
  final String keywords;

  /// The five skin-tone variants (light → dark), for emoji that have them.
  final List<String>? tones;

  bool get hasTones => tones != null;

  /// The glyph for skin tone [tone] (0 = none, 1–5 = light → dark).
  String withTone(int tone) {
    final t = tones;
    if (t == null || tone < 1 || tone > t.length) return char;
    return t[tone - 1];
  }

  bool matches(String query) =>
      name.contains(query) || keywords.contains(query);
}

/// Every unicode emoji, in Unicode's own group order, with the short names
/// used by `:shortcode:` autocomplete. Generated into `emoji_catalog_data.dart`
/// by `tool/make_emoji_catalog.py` (short names and keywords curated in
/// `tool/emoji_shortnames.py`). Custom space emoji are layered on top by the
/// picker.

/// Shortcode-name → unicode-char lookup, built once from [kEmojiCatalog].
final Map<String, String> _emojiByName = {
  for (final e in kEmojiCatalog) e.name: e.char,
};

/// A reaction emoji's identity: a [name] (unicode shortcode or custom-emoji
/// name) plus an optional custom-emoji [id].
typedef EmojiRef = ({String name, String? id});

/// Splits an emoji reference into its name and optional custom-emoji id.
///
/// Custom emoji travel as `name:id` (id a numeric snowflake) in REST tokens and
/// in gateway reaction echoes, while unicode emoji arrive as a bare glyph or
/// shortcode. Recovering the id lets the UI load the image instead of rendering
/// `name:id` as literal text. A trailing `:` (the colon-wrapped shortcode form
/// `:hamburger:`) or any non-numeric tail is left untouched as part of [name].
EmojiRef parseEmojiToken(String value) {
  final i = value.lastIndexOf(':');
  if (i > 0 && i < value.length - 1) {
    final id = value.substring(i + 1);
    if (id.codeUnits.every((c) => c >= 0x30 && c <= 0x39)) {
      return (name: value.substring(0, i), id: id);
    }
  }
  return (name: value, id: null);
}

/// Resolves a unicode-emoji reference to its glyph. [value] may already be the
/// glyph (returned as-is), a bare shortcode (`hamburger`), or a colon-wrapped
/// shortcode (`:hamburger:`). Falls back to [value] when the shortcode isn't in
/// the catalog. Custom (image) emoji are handled elsewhere, by id.
String resolveEmojiGlyph(String value) {
  if (value.isEmpty) return value;
  // Any non-ASCII rune means it's already an emoji glyph, not a shortcode.
  if (value.runes.any((r) => r > 0x7F)) return value;
  final key = value.replaceAll(':', '');
  return _emojiByName[key] ?? value;
}
