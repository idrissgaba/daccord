part of 'message_pane.dart';

/// Attachments: file picking and drops, voice messages, polls, stickers and the emoji picker. Split from [_ComposerState] for size.
mixin _ComposerAttachments on ConsumerState<_Composer> {
  String? get _error;
  set _error(String? value);
  FocusNode get _focusNode;
  void _insertAtCursor(String text);
  Future<void> _send();
  bool get _sending;

  /// Files the user has attached but not yet sent.
  final List<PendingAttachment> _attachments = [];

  /// True while a voice message is being recorded: the recorder replaces the
  /// text field and its buttons.
  bool _recordingVoice = false;

  /// True while a file drag is hovering the composer, which swaps the hint for
  /// a drop prompt and outlines the box.
  bool _dragging = false;

  /// Opens the system file picker.
  ///
  /// No `allowedExtensions` filter: the Accord server enforces no type
  /// allow-list on message attachments (only size and count — see
  /// `AccordServerLimits`), so filtering here would hide legitimate files.
  /// Unrecognised types attach and upload; they just don't preview inline.
  ///
  /// The picker can throw rather than return null (Windows' legacy
  /// `GetOpenFileNameW` fails on a cloud placeholder or an over-MAX_PATH
  /// selection); unguarded, that escapes the unawaited `onPressed` and the
  /// attach button appears to do nothing.
  Future<void> _pickFiles() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
    } catch (e) {
      debugPrint('File picker failed: $e');
      if (mounted) {
        setState(() => _error = "Couldn't open the file picker: $e");
      }
      return;
    }
    if (result == null || !mounted) return;
    _addFiles([for (final file in result.files) PendingAttachment(file)]);
  }

  Future<void> _onDrop(DropDoneDetails details) async {
    setState(() => _dragging = false);
    if (_sending) return;
    final dropped = await readDroppedFiles(
      details.files,
      maxBytes: ref.read(serverLimitsControllerProvider).maxAttachmentBytes,
    );
    if (!mounted) return;
    _addFiles(dropped.accepted, alsoRejected: dropped.rejections);
  }

  /// Attaches every file in [files] that passes the connected server's
  /// limits, and reports the ones that don't, along with any [alsoRejected]
  /// lines the caller screened out itself. A file dropped in silence would
  /// look like the attach button doing nothing.
  void _addFiles(
    Iterable<PendingAttachment> files, {
    List<String> alsoRejected = const [],
  }) {
    final limits = ref.read(serverLimitsControllerProvider);
    final screened = screenAttachments(
      files,
      maxBytes: limits.maxAttachmentBytes,
      maxCount: limits.maxAttachmentsPerMessage,
      alreadyAttached: _attachments.length,
    );
    final rejections = [...alsoRejected, ...screened.rejections];
    setState(() {
      _attachments.addAll(screened.accepted);
      _error = rejections.isEmpty ? null : rejections.join('\n');
    });
  }

  void _startVoiceMessage() {
    setState(() {
      _recordingVoice = true;
      _error = null;
    });
  }

  /// A finished voice message is sent straight away, like any attachment.
  void _onVoiceMessageRecorded(PendingAttachment file) {
    setState(() => _recordingVoice = false);
    _addFiles([file]);
    if (_attachments.contains(file)) unawaited(_send());
  }

  void _onVoiceMessageClosed(String? error) {
    if (!mounted) return;
    setState(() {
      _recordingVoice = false;
      _error = error;
    });
  }

  void _createPoll() {
    final client = ref.accordClient;
    if (client == null) return;
    final controller = ref.read(
      accordMessagesControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.channelId,
      ).notifier,
    );
    showCreatePollDialog(
      context,
      create:
          ({
            required question,
            required answers,
            required allowMultiselect,
            required durationHours,
          }) => controller.createPoll(
            client,
            question: question,
            answers: answers,
            allowMultiselect: allowMultiselect,
            durationHours: durationHours,
          ),
    );
  }

  void _removeAttachment(PendingAttachment file) {
    setState(() => _attachments.remove(file));
  }

  Future<void> _pickEmoji() async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    _insertAtCursor(pick.composerText);
  }

  /// Sends a sticker picked from the spaces we belong to.
  Future<void> _pickSticker() async {
    final spaceId = widget.spaceId;
    if (spaceId == null) return;
    final sticker = await showStickerPicker(context, spaceId: spaceId);
    final client = ref.accordClient;
    if (sticker == null || client == null || !mounted) return;
    final result = await client.stickers.send(widget.channelId, sticker.id);
    if (!mounted) return;
    final message = result.data;
    if (result.ok && message is AccordMessage) {
      ref
          .read(
            accordMessagesControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.channelId,
            ).notifier,
          )
          .addMessage(message);
    } else {
      setState(
        () => _error = result.errorMessageOr('Could not send the sticker'),
      );
    }
    _focusNode.requestFocus();
  }
}
