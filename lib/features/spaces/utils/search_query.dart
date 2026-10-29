/// A search box query split into its free text and its `key:value` filters,
/// the way other chat apps read `from:`, `in:`, `before:`, `after:` and
/// `pinned:`. Values are kept raw here; the dialog resolves names to ids.
class ParsedSearchQuery {
  const ParsedSearchQuery({
    required this.text,
    this.from,
    this.inChannel,
    this.before,
    this.after,
    this.pinned,
  });

  final String text;

  /// `from:@name` / `from:name`, without the `@`.
  final String? from;

  /// `in:#name` / `in:name`, without the `#`.
  final String? inChannel;

  /// `before:YYYY-MM-DD` and `after:YYYY-MM-DD`, as typed when they parse.
  final String? before;
  final String? after;

  /// `pinned:true` / `pinned:false`.
  final bool? pinned;

  bool get hasFilters =>
      from != null ||
      inChannel != null ||
      before != null ||
      after != null ||
      pinned != null;
}

final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

ParsedSearchQuery parseSearchQuery(String raw) {
  String? from, inChannel, before, after;
  bool? pinned;
  final words = <String>[];
  for (final token in raw.trim().split(RegExp(r'\s+'))) {
    if (token.isEmpty) continue;
    final colon = token.indexOf(':');
    if (colon <= 0 || colon == token.length - 1) {
      words.add(token);
      continue;
    }
    final key = token.substring(0, colon).toLowerCase();
    final value = token.substring(colon + 1);
    switch (key) {
      case 'from':
        from = value.startsWith('@') ? value.substring(1) : value;
      case 'in':
        inChannel = value.startsWith('#') ? value.substring(1) : value;
      case 'before' when _date.hasMatch(value):
        before = value;
      case 'after' when _date.hasMatch(value):
        after = value;
      case 'pinned' when value == 'true' || value == 'false':
        pinned = value == 'true';
      default:
        words.add(token);
    }
  }
  return ParsedSearchQuery(
    text: words.join(' '),
    from: from,
    inChannel: inChannel,
    before: before,
    after: after,
    pinned: pinned,
  );
}
