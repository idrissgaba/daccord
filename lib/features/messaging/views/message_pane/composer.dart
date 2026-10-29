part of 'message_pane.dart';

/// Linux: the channel the composer uses as an ordering barrier with the GTK
/// embedder before a plain-Enter send.
///
/// Nothing on the platform side handles it, so `fl_engine.cc` answers it with
/// an empty reply straight away, on the platform thread, in order with the key
/// responses it already has queued. By the time that reply reaches Dart,
/// every text-input update GTK produced for keys typed before the Enter has
/// been delivered. See [_ComposerState._sendAfterNativeEdits].
@visibleForTesting
const composerNativeInputBarrierChannel = 'daccord/composer/input_barrier';

/// A mention that pings everyone, which the send confirms first.
final _broadcastMention = RegExp(r'@(everyone|here)\b');

class _Composer extends ConsumerStatefulWidget {
  const _Composer({
    required this.channelId,
    this.channelName,
    this.spaceId,
    required this.canMentionEveryone,
    this.slowmodeSeconds = 0,
    this.replyingTo,
    this.replyName,
    this.onCancelReply,
    this.onEditLastMessage,
  });

  final String channelId;
  final String? channelName;
  final String? spaceId;
  final bool canMentionEveryone;

  /// ↑ in an empty composer: opens the inline editor on the current user's
  /// most recent message in this channel (null when there is none).
  final VoidCallback? onEditLastMessage;

  /// The channel's slowmode in seconds, or 0 when it's off or the current
  /// user is exempt (see `effectiveSlowmodeSeconds`). Starts a local cooldown
  /// after each accepted send and picks the wording of a 429 countdown.
  final int slowmodeSeconds;
  final AccordMessage? replyingTo;
  final String? replyName;
  final VoidCallback? onCancelReply;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer>
    with
        _ComposerAttachments,
        _ComposerMentions,
        _ComposerEmojiSuggest,
        _ComposerCommands,
        _ComposerView {
  @override
  final _controller = TextEditingController();
  @override
  final _focusNode = FocusNode();
  @override
  bool _sending = false;

  /// Why the last attach or send didn't work, shown above the composer.
  /// Cleared when the user attaches again or retries the send.
  @override
  String? _error;

  /// The send cooldown in force — slowmode after an accepted send, or the
  /// `retry_after` of a server 429 — and the once-a-second tick that redraws
  /// its countdown. Nothing resends when it lapses: the user retries. Dropped
  /// on channel or account change, since it belongs to this channel alone.
  @override
  SendCooldown? _cooldown;
  Timer? _cooldownTicker;

  /// The server's typing indicator lasts ~10s, so we re-trigger at most once
  /// every 8s while the user keeps typing rather than on every keystroke.
  DateTime? _lastTypingSent;
  static const _typingInterval = Duration(seconds: 8);

  /// Captured once so `dispose()` can persist the draft without touching `ref`,
  /// which Riverpod tears down before `dispose()` runs. Safe because
  /// `SettingsController` is `keepAlive`, so this notifier outlives the widget.
  late final SettingsController _settings;
  @override
  late String _serverKey;

  /// Text pastes longer than this prompt to send as a `.txt` attachment.
  static const _largePasteThreshold = 2000;

  @override
  void initState() {
    super.initState();
    _settings = ref.read(settingsControllerProvider.notifier);
    _serverKey = ref.readActiveServerKey() ?? '';
    _controller.text = ref
        .read(settingsControllerProvider)
        .draftFor(_serverKey, widget.channelId);
    // Intercept Ctrl/Cmd+V to support pasting images and large text (the
    // EditableText's own paste only handles inline text), and Shift+Enter to
    // insert a newline instead of sending.
    _focusNode.onKeyEvent = _onComposerKey;
  }

  KeyEventResult _onComposerKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final mods = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final plain =
        !mods.isShiftPressed &&
        !mods.isControlPressed &&
        !mods.isMetaPressed &&
        !mods.isAltPressed;
    // While the mention popup has candidates it owns ↑/↓, Tab, Enter and
    // Escape; Enter used to send the half-typed `@idr` instead.
    if (_mention != null && widget.spaceId != null) {
      final result = _onMentionKey(event, mods);
      if (result != null) return result;
    }
    if (_emojiSuggest != null) {
      final result = _onEmojiSuggestKey(event, mods);
      if (result != null) return result;
    }
    // Ctrl+E opens the emoji picker, as in other chat apps.
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.keyE &&
        (mods.isControlPressed || mods.isMetaPressed) &&
        !mods.isShiftPressed &&
        !mods.isAltPressed) {
      if (!_sending) _pickEmoji();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && key == LogicalKeyboardKey.escape) {
      if (widget.replyingTo != null && widget.onCancelReply != null) {
        widget.onCancelReply!();
        return KeyEventResult.handled;
      }
    }
    // ↑ in an empty composer edits the last message you sent.
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.arrowUp &&
        plain &&
        _controller.text.isEmpty &&
        widget.onEditLastMessage != null) {
      widget.onEditLastMessage!();
      return KeyEventResult.handled;
    }
    if (kIsWeb) {
      // Browsers deliver clipboard contents through the focused HTML editor's
      // paste/input event. Consuming Ctrl/Cmd+V cancels that event, and the
      // async Clipboard API may be unavailable or require a separate
      // permission, so paste stays with the browser. Shift+Enter is still
      // claimed: the HTML editor behind a `send` field submits on it exactly
      // like the desktop embedders do, and it sent the message instead of
      // breaking the line.
      if (isShiftEnterChord(event, mods) && !_isComposing) {
        _insertAtCursor('\n');
        _onChanged(_controller.text);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (composerUsesNativeNewlines) {
      if (_awaitingNativeEdits) {
        // A plain-Enter send is waiting for GTK's earlier edits. Keys must not
        // reach GTK now, or their updates would be computed on the draft that
        // is about to be cleared. Keep their text and replay it after.
        final text = bufferedKeyText(event, mods);
        if (text != null) _typedWhileAwaiting.write(text);
        return KeyEventResult.handled;
      }
      if (isPlainEnter(event, mods) && !_isComposing) {
        // Held Enter repeats are swallowed: they must neither resend nor
        // fall through to the embedder as newlines.
        if (event is KeyDownEvent) _sendAfterNativeEdits();
        return KeyEventResult.handled;
      }
      // Shift+Enter (and Enter with any other modifier, or during a
      // composition) goes to GTK's input method and then the embedder, which
      // inserts the newline itself. See [composerUsesNativeNewlines].
    } else if (isShiftEnterChord(event, mods) && !_isComposing) {
      _insertAtCursor('\n');
      _onChanged(_controller.text);
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final isPaste =
        (mods.isControlPressed || mods.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (!isPaste) return KeyEventResult.ignored;
    // Consume and handle the paste ourselves (image / large-text aware).
    _handlePaste();
    return KeyEventResult.handled;
  }

  /// Whether the IME has reported a composition. Enter is left to the IME
  /// then, because it commits the candidate.
  bool get _isComposing {
    final composing = _controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  @override
  void _onSubmitted() {
    // EditableText unfocuses on a `send` action just before onSubmitted runs;
    // the field is enabled, so asking for focus straight back lands in the
    // same frame. (Not reached on Linux: see [composerUsesNativeNewlines].)
    _focusNode.requestFocus();
    _send();
  }

  /// Linux: a plain-Enter send is waiting for [_sendAfterNativeEdits]'s
  /// barrier.
  bool _awaitingNativeEdits = false;

  /// Text typed while [_awaitingNativeEdits], replayed after the send.
  final StringBuffer _typedWhileAwaiting = StringBuffer();

  /// Linux plain Enter: sends only once GTK has delivered every edit for keys
  /// typed before the Enter.
  ///
  /// Key events reach Dart before GTK's text update for them, so with
  /// `x Return` typed fast the Enter arrives while the `x` update is still
  /// queued, and reading the draft straight away would leave `x` behind.
  /// A round trip on [composerNativeInputBarrierChannel] is answered only
  /// after those queued updates, so the draft is complete when it returns.
  ///
  /// Keys pressed in that window (about a millisecond) are claimed and
  /// buffered by the key handler. If they reached GTK, it would apply them to
  /// the draft being sent, and the late update would bring that draft back
  /// after the clear. [_send] then reads and clears the draft synchronously,
  /// and the buffered text is inserted into the cleared field. That field edit
  /// reaches GTK before any later key does. The text-input connection is never
  /// restarted.
  Future<void> _sendAfterNativeEdits() async {
    _awaitingNativeEdits = true;
    try {
      await const BasicMessageChannel<Object?>(
        composerNativeInputBarrierChannel,
        StandardMessageCodec(),
      ).send(null).timeout(const Duration(milliseconds: 250));
    } catch (_) {
      // No reply only costs the ordering guarantee; don't leave Enter dead.
    }
    if (!mounted) return;
    _awaitingNativeEdits = false;
    final typed = _typedWhileAwaiting.toString();
    _typedWhileAwaiting.clear();
    _send();
    if (typed.isNotEmpty) {
      _insertAtCursor(typed);
      _onChanged(_controller.text);
    }
  }

  /// Handles a clipboard paste: an image becomes a pending attachment; very
  /// large text prompts to attach it as a `.txt` file; otherwise the text is
  /// inserted inline. Ports the reference composer's paste handling.
  Future<void> _handlePaste() async {
    Uint8List? image;
    try {
      image = await Pasteboard.image;
    } catch (_) {}
    if (!mounted) return;
    if (image != null && image.isNotEmpty) {
      // The clipboard image isn't necessarily a PNG; sniff the bytes so the
      // name matches the content.
      _addFiles([
        PendingAttachment.fromBytes(
          name: pastedImageFilename(image),
          bytes: image,
        ),
      ]);
      return;
    }

    var text = '';
    try {
      text = await Pasteboard.text ?? '';
    } catch (_) {}
    if (!mounted || text.isEmpty) return;

    if (text.length > _largePasteThreshold) {
      final asFile = await _confirmLargePaste(text.length);
      if (!mounted || asFile == null) return;
      if (asFile) {
        final bytes = Uint8List.fromList(utf8.encode(text));
        _addFiles([
          PendingAttachment.fromBytes(name: 'message.txt', bytes: bytes),
        ]);
        return;
      }
    }
    _insertAtCursor(text);
  }

  /// Asks whether a large paste should become a `.txt` attachment. Returns true
  /// (file), false (inline), or null (cancelled).
  Future<bool?> _confirmLargePaste(int length) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste large text'),
        content: Text(
          "That's a lot of text ($length characters). Attach it as a .txt "
          'file instead of pasting inline?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Paste inline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Attach as file'),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(_Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reply started from a message's hover bar or menu lands the caret
    // here: typing straight after "Reply" went nowhere otherwise.
    final reply = widget.replyingTo;
    if (reply != null && reply.id != oldWidget.replyingTo?.id) {
      _focusNode.requestFocus();
    }
    final nextServerKey = ref.readActiveServerKey() ?? '';
    if (oldWidget.channelId != widget.channelId ||
        nextServerKey != _serverKey) {
      // Channel switched within the same composer instance: persist the
      // outgoing channel's draft and restore the incoming channel's.
      _saveDraft(oldWidget.channelId, _controller.text);
      _controller.text = ref
          .read(settingsControllerProvider)
          .draftFor(nextServerKey, widget.channelId);
      _serverKey = nextServerKey;
      _lastTypingSent = null;
      _slashQuery = null;
      _command = null;
      // The cooldown was this channel's (or this account's); a rebuild is
      // already underway, so no setState.
      _cooldownTicker?.cancel();
      _cooldownTicker = null;
      _cooldown = null;
      // A recording in progress belonged to the old channel: dropping the
      // recorder from the tree discards it rather than sending it here.
      _recordingVoice = false;
    } else if (widget.slowmodeSeconds == 0 &&
        oldWidget.slowmodeSeconds > 0 &&
        _cooldown?.kind == SendCooldownKind.slowmode) {
      // Slowmode was switched off, or the user just became exempt.
      _cooldownTicker?.cancel();
      _cooldownTicker = null;
      _cooldown = null;
    }
  }

  /// Whether Send is withheld by the cooldown right now.
  bool get _sendBlocked => sendBlockedByCooldown(
    cooldown: _cooldown,
    now: DateTime.now(),
    hasAttachments: _attachments.isNotEmpty,
  );

  /// Installs [cooldown] (replacing any running one) and ticks the countdown
  /// once a second until it lapses. A null or already-expired cooldown clears.
  void _startCooldown(SendCooldown? cooldown) {
    _cooldownTicker?.cancel();
    _cooldownTicker = null;
    if (cooldown == null || !cooldown.isActive(DateTime.now())) {
      if (_cooldown != null) setState(() => _cooldown = null);
      return;
    }
    setState(() => _cooldown = cooldown);
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final current = _cooldown;
      if (current == null || !current.isActive(DateTime.now())) {
        _clearCooldown();
        return;
      }
      setState(() {});
    });
  }

  void _clearCooldown() {
    _cooldownTicker?.cancel();
    _cooldownTicker = null;
    if (_cooldown == null) return;
    setState(() => _cooldown = null);
  }

  /// Persists [text] as the draft for [channelId] (mirrors the reference
  /// client's `Config.set_draft_text`).
  @override
  void _saveDraft(String channelId, String text) {
    _settings.setDraft(_serverKey, channelId, text);
  }

  @override
  void dispose() {
    _cooldownTicker?.cancel();
    _saveDraft(widget.channelId, _controller.text);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void _onChanged(String value) {
    _updateMentionState(value);
    _updateEmojiSuggestState(value);
    _updateSlashState(value);
    if (value.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _typingInterval) {
      return;
    }
    _lastTypingSent = now;
    ref.accordClient?.messages.typing(widget.channelId);
  }

  @override
  void _insertAtCursor(String text) {
    _controller.value = insertAtSelection(_controller.value, text);
    _focusNode.requestFocus();
  }

  @override
  Future<void> _send() async {
    // Emoticons convert on send, not on render, so the stored content holds the
    // real glyph for every other client (and for edit/copy here).
    final raw = _controller.text;
    final text =
        ref.read(settingsControllerProvider.select((s) => s.convertEmoticons))
        ? applyEmoticons(raw)
        : raw;
    if ((text.trim().isEmpty && _attachments.isEmpty) || _sending) return;
    if (_sendAsCommand(text)) return;
    // Enter/Send during a cooldown does nothing; the countdown says why.
    if (_sendBlocked) return;

    final client = ref.accordClient;
    if (client == null) return;

    final controller = ref.read(
      accordMessagesControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.channelId,
      ).notifier,
    );
    final replyTo = widget.replyingTo?.id;
    final attachments = List<PendingAttachment>.of(_attachments);
    // Content type resolved when the file was attached (magic bytes → platform
    // MIME → extension table), not re-guessed from the extension here.
    final files = [for (final file in attachments) file.toUploadPart()];
    // Empty the composer up front rather than after the round-trip. The field
    // is never disabled (that would drop focus and the mobile keyboard for the
    // whole send), so it has to be free for the next message straight away;
    // everything cleared here comes back if the send fails.
    _controller.clear();
    _saveDraft(widget.channelId, '');
    _lastTypingSent = null;
    setState(() {
      _sending = true;
      _error = null;
      _attachments.clear();
      _mention = null;
      _emojiSuggest = null;
    });

    SendFailure? error;
    try {
      error = await controller.sendWithAttachments(
        client,
        text,
        files,
        replyTo: replyTo,
      );
    } catch (e) {
      // Escaping this unawaited callback would leave the composer stuck
      // sending, with the user's text and attachments gone.
      debugPrint('Send failed: $e');
      error = SendFailure('Failed to send: $e');
    }
    if (!mounted) return;
    if (error == null) {
      setState(() => _sending = false);
      // Slowmode: the server will refuse another message for this long, so
      // don't offer one. Its 429 corrects this timer if the clocks disagree.
      _startCooldown(
        cooldownAfterSend(
          slowmodeSeconds: widget.slowmodeSeconds,
          now: DateTime.now(),
        ),
      );
      soundManager.play('message_sent');
      widget.onCancelReply?.call();
      return;
    }
    // Failed: hand the message back so it can be fixed and retried, keeping any
    // attachments ahead of ones added while this send was in flight. A rate
    // limit (slowmode or an upload budget) becomes a countdown rather than an
    // error to dismiss — the server's retry_after is the whole story, and the
    // message was sent exactly once, so there is nothing to retry until then.
    final cooldown = cooldownFromFailure(
      failure: error,
      hasAttachments: attachments.isNotEmpty,
      slowmodeSeconds: widget.slowmodeSeconds,
      now: DateTime.now(),
    );
    final errorText = cooldown == null ? error.message : null;
    setState(() {
      _sending = false;
      _error = errorText;
      _attachments.insertAll(0, attachments);
    });
    restoreFailedSend(_controller, text);
    _saveDraft(widget.channelId, _controller.text);
    if (cooldown != null) _startCooldown(cooldown);
  }
}
