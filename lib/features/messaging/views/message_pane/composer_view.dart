part of 'message_pane.dart';

/// The composer's widget tree. Split from [_ComposerState] for size; the state keeps the behaviour, this keeps the layout.
mixin _ComposerView
    on
        ConsumerState<_Composer>,
        _ComposerMentions,
        _ComposerEmojiSuggest,
        _ComposerCommands,
        _ComposerAttachments {
  SendCooldown? get _cooldown;
  void _onChanged(String value);
  void _onSubmitted();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Watched, not read: the limits arrive a round-trip after connect, and the
    // attach button's enabled state depends on the count limit.
    final limits = ref.watch(serverLimitsControllerProvider);
    final atAttachmentLimit =
        _attachments.length >= limits.maxAttachmentsPerMessage;
    final name = widget.channelName;
    // DMs have no `#`: the pane passes the conversation's title, and the
    // placeholder reads "Message @name". A nameless channel stays "Message"
    // rather than a dangling "Message #".
    final hint = _dragging
        ? 'Drop files to attach'
        : name == null || name.isEmpty
        ? 'Message'
        : widget.spaceId == null
        ? 'Message @$name'
        : 'Message #$name';
    final now = DateTime.now();
    final cooldown = _cooldown != null && _cooldown!.isActive(now)
        ? _cooldown
        : null;
    final sendBlocked = sendBlockedByCooldown(
      cooldown: cooldown,
      now: now,
      hasAttachments: _attachments.isNotEmpty,
    );
    // A voice message is an upload, so an upload budget holds it back too.
    final voiceBlocked = sendBlockedByCooldown(
      cooldown: cooldown,
      now: now,
      hasAttachments: true,
    );
    // Configured capacity, shown as guidance beside the per-message limits;
    // only the server knows what's left this minute.
    final budgetHint = uploadBudgetHint(
      requestsPerMinute: limits.uploadRequestsPerMinute,
      bytesPerMinute: limits.uploadBytesPerMinute,
    );
    final String? cooldownLine = cooldown != null
        ? [
            sendCooldownLabel(cooldown, now),
            if (cooldown.kind == SendCooldownKind.rateLimited &&
                budgetHint != null)
              budgetHint,
          ].join(' ')
        : widget.slowmodeSeconds > 0
        ? slowmodeHint(widget.slowmodeSeconds)
        : null;
    // A DropTarget keeps receiving drags even when covered, so it's disabled
    // while a dialog/sheet (emoji picker, lightbox, …) is on top of the pane.
    final onTop = ModalRoute.of(context)?.isCurrent ?? true;
    return DropTarget(
      enable: !_sending && onTop,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDrop,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            // A shade lighter than the chat, so the box reads as a field.
            color: Color.lerp(colors.background, colors.dirtyWhite, 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _dragging ? colors.primary : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.replyingTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 4, 0),
                  child: Row(
                    children: [
                      Icon(Icons.reply, size: 14, color: colors.gray),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Replying to ${widget.replyName ?? 'message'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.labelMedium!.copyWith(color: colors.gray),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel reply',
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onCancelReply,
                        icon: Icon(Icons.close, size: 14, color: colors.gray),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: InlineError(_error!, centered: false)),
                      IconButton(
                        tooltip: 'Dismiss',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _error = null),
                        icon: Icon(Icons.close, size: 14, color: colors.gray),
                      ),
                    ],
                  ),
                ),
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final file in _attachments)
                        _AttachmentChip(
                          attachment: file,
                          onRemove: _sending
                              ? null
                              : () => _removeAttachment(file),
                        ),
                    ],
                  ),
                ),
              if (!widget.canMentionEveryone)
                // Follows the text itself: pastes and programmatic edits don't
                // otherwise rebuild the composer.
                ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (context, value, _) =>
                      _broadcastMention.hasMatch(value.text)
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "You don't have permission to mention @everyone or @here in this channel.",
                              style: Theme.of(context).textTheme.bodySmall!
                                  .copyWith(color: colors.yellow),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              if (cooldownLine != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: cooldown != null ? colors.yellow : colors.gray,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cooldownLine,
                          style: Theme.of(context).textTheme.bodySmall!
                              .copyWith(
                                color: cooldown != null
                                    ? colors.yellow
                                    : colors.gray,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_mention != null && widget.spaceId != null)
                _MentionPopup(
                  spaceId: widget.spaceId!,
                  query: _mention!.query,
                  allowBroadcast: widget.canMentionEveryone,
                  onPick: _pickMention,
                  highlighted: _mentionIndex,
                ),
              if (_emojiSuggest != null && _mention == null)
                _EmojiSuggestPopup(
                  entries: _emojiSuggestions(),
                  query: _emojiSuggest!.query,
                  onPick: _pickEmojiSuggestion,
                  highlighted: _emojiIndex,
                ),
              if (_slashQuery != null &&
                  _command == null &&
                  widget.spaceId != null)
                CommandPopup(
                  serverKey: _serverKey,
                  spaceId: widget.spaceId!,
                  query: _slashQuery!,
                  onPick: _pickCommand,
                ),
              InteractionStatusLine(channelId: widget.channelId),
              if (_recordingVoice)
                VoiceMessageRecorder(
                  onRecorded: _onVoiceMessageRecorded,
                  onClosed: _onVoiceMessageClosed,
                )
              else if (_command != null && widget.spaceId != null)
                CommandForm(
                  key: ValueKey('command-form-${_command!.id}'),
                  serverKey: _serverKey,
                  spaceId: widget.spaceId!,
                  command: _command!,
                  onRun: (options) => _runCommand(_command!, options),
                  onCancel: _cancelCommand,
                )
              else
                Row(
                  children: [
                    IconButton(
                      tooltip: atAttachmentLimit
                          ? 'Attachment limit reached '
                                '(${limits.maxAttachmentsPerMessage} per message)'
                          : [
                              'Attach files '
                                  '(${attachmentLimitsHint(maxBytes: limits.maxAttachmentBytes, maxCount: limits.maxAttachmentsPerMessage)})',
                              if (budgetHint != null) budgetHint,
                            ].join('\n'),
                      onPressed: _sending || atAttachmentLimit
                          ? null
                          : _pickFiles,
                      icon: Icon(
                        Icons.add_circle_outline,
                        size: 20,
                        color: atAttachmentLimit
                            ? colors.gray
                            : colors.dirtyWhite,
                      ),
                    ),
                    if (widget.spaceId != null)
                      IconButton(
                        key: const Key('poll-create'),
                        tooltip: 'Create a poll',
                        onPressed: _sending ? null : _createPoll,
                        icon: Icon(
                          Icons.poll_outlined,
                          size: 20,
                          color: colors.dirtyWhite,
                        ),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        // Deliberately never disabled while sending: a disabled
                        // TextField gives up focus (and the mobile keyboard) for
                        // the whole round-trip. The buttons below and the guard
                        // in _send() are what stop a double-send.
                        minLines: 1,
                        maxLines: 6,
                        textInputAction: composerUsesNativeNewlines
                            ? TextInputAction.newline
                            : TextInputAction.send,
                        onChanged: _onChanged,
                        onSubmitted: (_) => _onSubmitted(),
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: hint,
                          hintStyle: Theme.of(
                            context,
                          ).textTheme.bodyLarge!.copyWith(color: colors.gray),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Emoji',
                      onPressed: _sending ? null : _pickEmoji,
                      icon: Icon(
                        Icons.emoji_emotions_outlined,
                        size: 20,
                        color: colors.dirtyWhite,
                      ),
                    ),
                    if (widget.spaceId != null)
                      IconButton(
                        key: const Key('sticker-pick'),
                        tooltip: 'Stickers',
                        onPressed: _sending ? null : _pickSticker,
                        icon: Icon(
                          Icons.sticky_note_2_outlined,
                          size: 20,
                          color: colors.dirtyWhite,
                        ),
                      ),
                    ValueListenableBuilder(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        // Nothing typed or attached: the send slot records a
                        // voice message instead.
                        if (value.text.trim().isEmpty && _attachments.isEmpty) {
                          return IconButton(
                            key: const Key('voice-message-record'),
                            tooltip: voiceBlocked && cooldown != null
                                ? sendCooldownLabel(cooldown, now)
                                : 'Record a voice message',
                            onPressed: _sending || voiceBlocked
                                ? null
                                : _startVoiceMessage,
                            icon: Icon(
                              Icons.mic_none,
                              size: 20,
                              color: voiceBlocked
                                  ? colors.gray
                                  : colors.dirtyWhite,
                            ),
                          );
                        }
                        return IconButton(
                          tooltip: sendBlocked && cooldown != null
                              ? sendCooldownLabel(cooldown, now)
                              : 'Send',
                          onPressed: _sending || sendBlocked ? null : _send,
                          icon: Icon(
                            Icons.send,
                            size: 20,
                            color: sendBlocked
                                ? colors.gray
                                : colors.dirtyWhite,
                          ),
                        );
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
