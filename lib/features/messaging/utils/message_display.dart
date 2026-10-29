import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';

/// Join messages may contain an outdated name (including a legacy email
/// username). Resolve their text from the same current name as the header,
/// including the safe "Unknown" fallback while the author is loading.
String accordMessageText(AccordMessage message, {required String authorName}) {
  if (message.type == 'member_join') {
    return '$authorName joined the server.';
  }
  return message.content;
}

/// [content] as one plain line for previews (reply bar, pinned list, search
/// results): markdown markers dropped, `:shortcode:` turned into its emoji,
/// whitespace collapsed. Rendering previews raw showed `**gras** _italique_`.
String plainMessagePreview(String content) {
  var text = content
      // Fenced code: keep the code, drop the fences and language tag.
      .replaceAllMapped(RegExp(r'```[a-zA-Z0-9_+-]*\n?([\s\S]*?)```'), (m) => m[1]!)
      // Masked links [label](url) → label.
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\((https?://[^)]+)\)'), (m) => m[1]!)
      // Line prefixes: headings, subtext, quotes, list bullets.
      .replaceAll(RegExp(r'^(#{1,3}|-#|>{1,3})\s+', multiLine: true), '')
      // Spoilers stay hidden in previews too.
      .replaceAll(RegExp(r'\|\|.+?\|\|'), '(spoiler)')
      // Inline markers.
      .replaceAllMapped(
        RegExp(r'(\*\*\*|\*\*|__|~~|\*|_|`)(.+?)\1'),
        (m) => m[2]!,
      );
  text = text.replaceAllMapped(RegExp(r':([a-z0-9_+-]+):'), (m) {
    final glyph = resolveEmojiGlyph(m[0]!);
    return glyph == m[0] || glyph.isEmpty ? m[0]! : glyph;
  });
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
