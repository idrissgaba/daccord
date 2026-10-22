/// Forwarding re-posts a message elsewhere as a quoted snapshot under a
/// "Forwarded" line, after the sender's optional comment. It is plain message
/// text (plus re-uploaded files), so every client and server can show it.
library;

/// The server's message length limit.
const int maxForwardedMessageLength = 4000;

/// The text of a forwarded message.
///
/// [sourceLabel] names where it came from (`#general`, `a direct message`),
/// [link] jumps back to the original when the reader can open it. The quoted
/// original is shortened with an ellipsis so the whole stays within
/// [maxLength].
String forwardedMessageContent({
  required String original,
  required String authorName,
  required String sourceLabel,
  String? link,
  String comment = '',
  int maxLength = maxForwardedMessageLength,
}) {
  final note = comment.trim();
  final prefix = note.isEmpty ? '' : '$note\n\n';
  final header = StringBuffer('-# ↪ Forwarded from $sourceLabel · $authorName');
  if (link != null && link.isNotEmpty) {
    header.write(' · [Jump to original]($link)');
  }

  final body = original.trim();
  if (body.isEmpty) return '$prefix$header';

  var quote = body.split('\n').map((line) => '> $line').join('\n');
  final budget = maxLength - prefix.length - header.length - 1;
  if (budget <= 3) return '$prefix$header';
  if (quote.length > budget) {
    quote = '${quote.substring(0, budget - 1).trimRight()}…';
  }
  return '$prefix$header\n$quote';
}
