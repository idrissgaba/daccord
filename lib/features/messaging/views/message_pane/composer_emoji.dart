part of 'message_pane.dart';

/// The `:shortcode` emoji popup: tracking the shortcode being typed, ↑/↓/Tab/
/// Enter in the list, and inserting the pick — the unicode glyph (in the
/// user's skin tone) or `:name:` for a custom space emoji. Split from
/// [_ComposerState] for size, like [_ComposerMentions].
mixin _ComposerEmojiSuggest on ConsumerState<_Composer> {
  TextEditingController get _controller;
  FocusNode get _focusNode;
  String get _serverKey;

  /// The `:query` being typed, or null when the popup is hidden.
  ({int start, int end, String query})? _emojiSuggest;

  /// The popup row ↑/↓ have moved to; back to the top on every new query.
  int _emojiIndex = 0;

  /// Keyboard for the emoji popup: ↑/↓ move the highlight, Tab or Enter
  /// insert the highlighted emoji, Escape closes it. Null when the key isn't
  /// the popup's or it has no candidates, so Enter still sends.
  KeyEventResult? _onEmojiSuggestKey(KeyEvent event, HardwareKeyboard mods) {
    final key = event.logicalKey;
    final isEnter = isPlainEnter(event, mods);
    final isTab = key == LogicalKeyboardKey.tab;
    final isUp = key == LogicalKeyboardKey.arrowUp;
    final isDown = key == LogicalKeyboardKey.arrowDown;
    final isEscape = key == LogicalKeyboardKey.escape;
    if (!(isEnter || isTab || isUp || isDown || isEscape)) return null;
    if (isEscape) {
      if (event is KeyDownEvent) setState(() => _emojiSuggest = null);
      return KeyEventResult.handled;
    }
    final entries = _emojiSuggestions();
    if (entries.isEmpty) return null;
    final index = _emojiIndex.clamp(0, entries.length - 1);
    if (isUp || isDown) {
      setState(
        () => _emojiIndex = (index + (isDown ? 1 : -1)) % entries.length,
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) _pickEmojiSuggestion(entries[index]);
    return KeyEventResult.handled;
  }

  /// The popup's current candidates, in the order it shows them: the space's
  /// custom emoji first, then unicode emoji whose short name starts with the
  /// query, then keyword matches.
  List<EmojiPick> _emojiSuggestions() {
    final suggest = _emojiSuggest;
    if (suggest == null) return const [];
    final tone = ref.read(settingsControllerProvider).emojiSkinTone;
    final spaceId = widget.spaceId;
    final custom = spaceId == null
        ? const <AccordEmoji>[]
        : ref.read(accordEmojisControllerProvider(_serverKey, spaceId)) ??
              const <AccordEmoji>[];
    return emojiSuggestionsFor(
      suggest.query,
      custom: custom,
      cdnUrl: ref.readCdnUrl(),
      tone: tone,
    );
  }

  /// Shows, updates or hides the emoji popup for the caret position.
  void _updateEmojiSuggestState(String text) {
    final suggest = findEmojiTrigger(text, _controller.value.selection);
    if (suggest == null && _emojiSuggest == null) return;
    setState(() {
      if (suggest?.query != _emojiSuggest?.query) _emojiIndex = 0;
      _emojiSuggest = suggest;
    });
  }

  /// Replaces the active `:query` with the pick's composer text and a space,
  /// and dismisses the popup.
  void _pickEmojiSuggestion(EmojiPick pick) {
    final suggest = _emojiSuggest;
    if (suggest == null || suggest.end > _controller.text.length) return;
    _controller.value = insertAtSelection(
      TextEditingValue(
        text: _controller.text,
        selection: TextSelection(
          baseOffset: suggest.start,
          extentOffset: suggest.end,
        ),
      ),
      '${pick.composerText} ',
    );
    if (widget.spaceId != null) {
      ref
          .read(settingsControllerProvider.notifier)
          .addRecentEmoji(pick.recentToken);
    }
    setState(() => _emojiSuggest = null);
    _focusNode.requestFocus();
  }
}

const int _maxEmojiSuggestions = 10;

/// Up to [_maxEmojiSuggestions] picks for [query]: custom emoji of the space
/// whose name contains it, then catalogue entries by short-name prefix, then
/// by keyword. Shared by the popup and the keyboard handling so Tab/Enter
/// insert exactly the highlighted row.
List<EmojiPick> emojiSuggestionsFor(
  String query, {
  required List<AccordEmoji> custom,
  required String? cdnUrl,
  required int tone,
}) {
  final q = query.toLowerCase();
  if (q.isEmpty) return const [];
  final out = <EmojiPick>[];
  for (final e in custom) {
    if (e.name.toLowerCase().contains(q)) {
      out.add(
        EmojiPick(name: e.name, id: e.id, imageUrl: accordEmojiUrl(e, cdnUrl)),
      );
      if (out.length >= _maxEmojiSuggestions) return out;
    }
  }
  final prefix = <EmojiPick>[];
  final contains = <EmojiPick>[];
  for (final e in kEmojiCatalog) {
    if (e.name.startsWith(q)) {
      prefix.add(EmojiPick(name: e.name, char: e.withTone(tone)));
    } else if (e.name.contains(q) || e.keywords.contains(q)) {
      contains.add(EmojiPick(name: e.name, char: e.withTone(tone)));
    }
    if (prefix.length >= _maxEmojiSuggestions) break;
  }
  out.addAll(prefix);
  out.addAll(contains);
  return out.length > _maxEmojiSuggestions
      ? out.sublist(0, _maxEmojiSuggestions)
      : out;
}

/// Compact `:shortcode` autocomplete popup rendered above the composer:
/// the glyph (or custom image) and its `:name:`, [highlighted] being the row
/// Tab or Enter inserts.
class _EmojiSuggestPopup extends StatelessWidget {
  const _EmojiSuggestPopup({
    required this.entries,
    required this.query,
    required this.onPick,
    this.highlighted = 0,
  });

  final List<EmojiPick> entries;
  final String query;
  final ValueChanged<EmojiPick> onPick;
  final int highlighted;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    if (entries.isEmpty) return const SizedBox.shrink();
    final highlightedIndex = highlighted.clamp(0, entries.length - 1);
    return Container(
      key: const Key('emoji-suggest-popup'),
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.foreground, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Text(
              'EMOJI MATCHING :$query',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: colors.gray,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final (index, pick) in entries.indexed)
            InkWell(
              onTap: () => onPick(pick),
              child: ColoredBox(
                color: index == highlightedIndex
                    ? colors.foreground
                    : Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: pick.isCustom && pick.imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: pick.imageUrl!,
                                fit: BoxFit.contain,
                              )
                            : Center(
                                child: Text(
                                  pick.char,
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ':${pick.name}:',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
