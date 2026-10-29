part of 'message_pane.dart';

/// What the row's hover bar and actions menu do: reactions, pins, threads, polls, forward, report, delete, block. Split from [_MessageRowState] for size.
mixin _MessageRowHandlers on ConsumerState<_MessageRow>, _MessageRowEditing {
  String get _authorName;
  AccordMessagesController? get _channelMessages;

  /// Whether the row's "⋯" actions menu is open. Only meaningful when [narrow],
  /// where the action bar is mounted on hover alone — see [_menuStateChanged].
  bool _menuOpen = false;

  void _openPopout(String authorId) {
    final spaceId = widget.spaceId;
    if (spaceId != null) {
      showAccordMemberPopout(context, spaceId: spaceId, userId: authorId);
      return;
    }
    final user = widget.authorUser;
    if (user != null) widget.onUserTap?.call(user);
  }

  void _openUserMenu([Offset? position]) {
    final user = widget.author?.user ?? widget.authorUser;
    if (user == null) return;
    widget.onUserContextMenu?.call(user, position);
  }

  /// Opens a popup listing the users who added [reaction], lazy-loaded.
  void _showReactors(String messageId, AccordReaction reaction) {
    showDialog<void>(
      context: context,
      builder: (_) => _ReactorsDialog(
        channelId: widget.channelId,
        messageId: messageId,
        emojiName: reaction.emoji['name']?.toString() ?? '',
        emojiId: reaction.emoji['id']?.toString(),
      ),
    );
  }

  Future<void> _toggleReaction(
    String messageId,
    String emojiName, {
    String? emojiId,
  }) async {
    final client = _client;
    if (client == null) return;
    // The optimistic badge is rolled back on failure; without this the reaction
    // just vanishes again with no explanation (#306).
    final error = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .toggleReaction(client, messageId, emojiName, emojiId: emojiId);
    if (error != null && mounted) showInfoSnack(context, error);
  }

  Future<void> _toggleSuperReaction(String messageId, String emoji) async {
    final client = _client;
    if (client == null) return;
    final error = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .toggleSuperReaction(client, messageId, emoji);
    if (error != null && mounted) showInfoSnack(context, error);
  }

  Future<void> _openSuperReactionPicker(String messageId) async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    final token = pick.id == null
        ? resolveEmojiGlyph(pick.name)
        : '${pick.name}:${pick.id}';
    await _toggleSuperReaction(messageId, token);
  }

  Future<void> _openReactionPicker(String messageId) async {
    final pick = await showAccordEmojiPicker(context, spaceId: widget.spaceId);
    if (pick == null || !mounted) return;
    await _toggleReaction(messageId, pick.name, emojiId: pick.id);
  }

  Future<void> _togglePin(String messageId, {required bool pinned}) async {
    final client = _client;
    if (client == null) return;
    final controller = ref.read(
      accordMessagesControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.channelId,
      ).notifier,
    );
    // As with reactions: the pin marker flips back on failure, so the reason has
    // to be reported or the action reads as a no-op (#306).
    final error = pinned
        ? await controller.unpin(client, messageId)
        : await controller.pin(client, messageId);
    if (error != null && mounted) showInfoSnack(context, error);
  }

  /// Keeps the floating action bar mounted for as long as its menu is open.
  ///
  /// When [_MessageRow.narrow] the bar is only built while the row is hovered,
  /// but opening a [PopupMenuButton] pushes a modal barrier that ends the hover
  /// — which unmounted the button mid-menu, and Flutter drops the selection
  /// when the button is gone (`if (!mounted) return` in `showButtonMenu`).
  /// Every item in that menu (delete, edit, pin, report) silently did nothing
  /// in the voice channel's chat panel as a result.
  void _menuStateChanged(bool open) {
    if (!mounted) return;
    setState(() => _menuOpen = open);
  }

  Future<void> _delete(String messageId) async {
    final client = _client;
    if (client == null || _busy) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete message',
      message: 'This message will be permanently deleted.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final ok = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .delete(client, messageId);
    if (!mounted) return;
    // Row disappears on success; if it failed we re-enable and say so, rather
    // than leaving the message sitting there as if nothing had been asked.
    setState(() => _busy = false);
    if (!ok) showInfoSnack(context, 'Failed to delete message');
  }

  Future<void> _blockFiles(AccordMessage message) async {
    final client = ref.accordClient;
    if (client == null) return;
    final removed = await showBlockAttachmentDialog(
      context,
      client: client,
      message: message,
      isInstanceAdmin: ref.readIsAdmin(),
      stillActive: () => mounted && identical(ref.accordClient, client),
    );
    if (mounted && removed == true && identical(ref.accordClient, client)) {
      ref
          .read(
            accordMessagesControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.channelId,
            ).notifier,
          )
          .removeMessage(message.id);
    }
  }

  Future<String?> _votePoll(
    String messageId,
    int answerId, {
    required bool remove,
  }) async {
    final client = ref.accordClient;
    final controller = _channelMessages;
    if (client == null || controller == null) return 'Not connected.';
    return controller.votePoll(client, messageId, answerId, remove: remove);
  }

  Future<void> _endPoll(String messageId) async {
    final client = ref.accordClient;
    final controller = _channelMessages;
    if (client == null || controller == null) return;
    final error = await controller.endPoll(client, messageId);
    if (error != null && mounted) showInfoSnack(context, error);
  }

  void _openThread(AccordMessage message) => showAccordThread(
    context,
    channelId: widget.channelId,
    spaceId: widget.spaceId,
    root: message,
    canManageMessages: widget.canManageMessages,
    onUserTap: widget.onUserTap,
    onUserContextMenu: widget.onUserContextMenu,
  );

  /// "Mark unread": this message and everything after it become unread again
  /// (here, on the server and on the user's other devices).
  void _markUnread(AccordMessage message) {
    final serverKey = ref.readActiveServerKey();
    if (serverKey == null) return;
    final loaded =
        ref.read(
          accordMessagesControllerProvider(serverKey, widget.channelId),
        ) ??
        const <AccordMessage>[];
    final position = readPositionBefore(loaded.map((m) => m.id), message.id);
    ref
        .read(readStateControllerProvider(serverKey).notifier)
        .markUnreadFrom(
          ref.read(accordAuthProvider.notifier).clientForKey(serverKey),
          widget.channelId,
          position,
          spaceId: widget.spaceId,
          latestMessageId: loaded.isEmpty ? message.id : loaded.last.id,
        );
  }

  /// Forwards [message] to another channel or direct message.
  void _forward(AccordMessage message) {
    final spaceId = widget.spaceId;
    final serverKey = ref.readActiveServerKey() ?? '';
    final channelName = spaceId == null
        ? null
        : ref
              .read(accordChannelsControllerProvider(serverKey, spaceId))
              ?.firstWhereOrNull((c) => c.id == widget.channelId)
              ?.name;
    showForwardMessageDialog(
      context,
      message: message,
      authorName: _authorName,
      sourceLabel: channelName != null
          ? '#$channelName'
          : spaceId == null
          ? 'a direct message'
          : 'a channel',
      spaceId: spaceId,
    );
  }

  /// Reports [message]. Available in DMs too, where [_MessageRow.spaceId] is
  /// null: the dialog then files an account-level report and offers to block
  /// the author, rather than the action disappearing (#290).
  void _report(AccordMessage message) {
    showReportDialog(
      context,
      spaceId: widget.spaceId,
      targetType: 'message',
      targetId: message.id,
      channelId: widget.channelId,
      reportedUserId: message.authorId.isEmpty ? null : message.authorId,
      reportedName: _authorName,
    );
  }

  /// The long-press (mobile) / right-click (desktop) message menu. Bulk-select
  /// lives here as one entry rather than being the long-press itself, so the
  /// per-message actions stay reachable on touch.
  ///
  /// [message] is captured when the menu opens: the entries' callbacks only run
  /// once the menu has closed (an await), by which point the row may already be
  /// bound to a different message.
  void _showActionsMenu(
    AccordMessage message, [
    Offset? position,
    VoidCallback? copySelection,
  ]) {
    if (_editing) return;
    final canDelete = widget.isOwn || widget.canManageMessages;
    final canReport = !widget.isOwn;
    final entries = <AccordMenuEntry>[
      if (copySelection != null)
        AccordMenuEntry(
          label: 'Copy selection',
          icon: Icons.content_copy,
          onSelected: copySelection,
        ),
      AccordMenuEntry(
        label: 'Add reaction',
        icon: Icons.add_reaction_outlined,
        onSelected: () => _openReactionPicker(message.id),
      ),
      AccordMenuEntry(
        label: 'Super reaction',
        icon: Icons.auto_awesome,
        onSelected: () => _openSuperReactionPicker(message.id),
      ),
      AccordMenuEntry(
        label: 'Reply',
        icon: Icons.reply,
        onSelected: widget.onReply,
      ),
      AccordMenuEntry(
        label: 'Thread',
        icon: Icons.forum_outlined,
        onSelected: () => _openThread(message),
      ),
      AccordMenuEntry(
        label: 'Forward',
        icon: Icons.shortcut,
        onSelected: () => _forward(message),
      ),
      AccordMenuEntry(
        label: 'Mark unread',
        icon: Icons.mark_chat_unread_outlined,
        onSelected: () => _markUnread(message),
      ),
      if (widget.spaceId case final spaceId?)
        AccordMenuEntry(
          label: 'Copy message link',
          icon: Icons.link,
          onSelected: () {
            Clipboard.setData(
              ClipboardData(
                text: messageLink(
                  spaceId: spaceId,
                  channelId: widget.channelId,
                  messageId: message.id,
                ),
              ),
            );
            showInfoSnack(context, 'Message link copied');
          },
        ),
      if (message.poll case final poll?
          when !poll.closed && (widget.isOwn || widget.canManageMessages))
        AccordMenuEntry(
          label: 'End poll',
          icon: Icons.stop_circle_outlined,
          onSelected: () => _endPoll(message.id),
        ),
      ...buildMessageActionEntries(
        content: accordMessageText(message, authorName: _authorName),
        canEdit: widget.isOwn,
        canDelete: canDelete,
        onEdit: () => _startEdit(message),
        onDelete: () => _delete(message.id),
        // Pin sits between Edit and Delete in this menu; it's site-specific
        // (the thread view has no pinning) so it slots in via [beforeDelete].
        beforeDelete: [
          if ((widget.canManageMessages || ref.readIsAdmin()) &&
              message.attachments.isNotEmpty &&
              (message.spaceId != null || ref.readIsAdmin()))
            AccordMenuEntry(
              label: 'Block files and delete',
              icon: Icons.block,
              onSelected: () => _blockFiles(message),
            ),
          if (widget.canManageMessages)
            AccordMenuEntry(
              label: message.pinned ? 'Unpin' : 'Pin',
              icon: message.pinned ? Icons.push_pin_outlined : Icons.push_pin,
              onSelected: () => _togglePin(message.id, pinned: message.pinned),
            ),
        ],
      ),
      if (canReport)
        AccordMenuEntry(
          label: 'Report',
          icon: Icons.flag_outlined,
          onSelected: () => _report(message),
        ),
      if (widget.onLongPressSelect != null) ...[
        const AccordMenuEntry.divider(),
        AccordMenuEntry(
          label: 'Select messages',
          icon: Icons.checklist,
          onSelected: widget.onLongPressSelect,
        ),
      ],
    ];

    showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: _authorName,
    );
  }
}
