part of 'message_pane.dart';

/// The @mention popup: tracking the handle being typed, ↑/↓/Tab/Enter in the list, and inserting the pick. Split from [_ComposerState] for size.
mixin _ComposerMentions on ConsumerState<_Composer> {
  TextEditingController get _controller;
  FocusNode get _focusNode;
  String get _serverKey;

  /// The `@` mention being typed, or null when the popup is hidden. A picked
  /// handle replaces its `[start, end)` range of `_controller.text`.
  ({int start, int end, String query})? _mention;

  /// The mention popup row ↑/↓ have moved to; back to the top on every new
  /// query.
  int _mentionIndex = 0;

  /// Keyboard for the mention popup: ↑/↓ move the highlight, Tab or Enter
  /// insert the highlighted handle, Escape closes it. Null when the key isn't
  /// the popup's or it has no candidates, so Enter still sends.
  KeyEventResult? _onMentionKey(KeyEvent event, HardwareKeyboard mods) {
    final key = event.logicalKey;
    final isEnter = isPlainEnter(event, mods);
    final isTab = key == LogicalKeyboardKey.tab;
    final isUp = key == LogicalKeyboardKey.arrowUp;
    final isDown = key == LogicalKeyboardKey.arrowDown;
    final isEscape = key == LogicalKeyboardKey.escape;
    if (!(isEnter || isTab || isUp || isDown || isEscape)) return null;
    if (isEscape) {
      if (event is KeyDownEvent) setState(() => _mention = null);
      return KeyEventResult.handled;
    }
    final entries = _mentionEntries();
    if (entries.isEmpty) return null;
    final index = _mentionIndex.clamp(0, entries.length - 1);
    if (isUp || isDown) {
      // Dart's % is never negative for a positive divisor, so ↑ on the first
      // row wraps to the last.
      setState(
        () => _mentionIndex = (index + (isDown ? 1 : -1)) % entries.length,
      );
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) _pickMention(entries[index].handle);
    return KeyEventResult.handled;
  }

  /// The popup's current candidates, in the order it shows them.
  List<_MentionEntry> _mentionEntries() {
    final spaceId = widget.spaceId;
    final mention = _mention;
    if (spaceId == null || mention == null) return const [];
    final members = ref.read(
      accordMembersControllerProvider(_serverKey, spaceId),
    );
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == spaceId);
    return _mentionCandidates(
      members,
      space?.roles ?? const <AccordRole>[],
      mention.query,
      allowBroadcast: widget.canMentionEveryone,
    );
  }

  /// Shows, updates or hides the mention popup for the caret position. The
  /// popup itself is only built when there are candidates to show.
  void _updateMentionState(String text) {
    final mention = widget.spaceId == null
        ? null
        : findMentionTrigger(text, _controller.value.selection);
    if (mention == null && _mention == null) return;
    setState(() {
      if (mention?.query != _mention?.query) _mentionIndex = 0;
      _mention = mention;
    });
  }

  /// Replaces the active `@query` with `@handle ` and dismisses the popup.
  /// Mirrors the reference's `_on_mention_picked`.
  void _pickMention(String handle) {
    final mention = _mention;
    if (mention == null || mention.end > _controller.text.length) return;
    _controller.value = insertAtSelection(
      TextEditingValue(
        text: _controller.text,
        selection: TextSelection(
          baseOffset: mention.start,
          extentOffset: mention.end,
        ),
      ),
      '@$handle ',
    );
    setState(() => _mention = null);
    _focusNode.requestFocus();
  }
}
