part of 'message_pane.dart';

class _MessageRow extends ConsumerStatefulWidget {
  const _MessageRow({
    super.key,
    required this.message,
    required this.channelId,
    required this.spaceId,
    required this.isOwn,
    required this.mentionsMe,
    required this.canManageMessages,
    required this.onReply,
    required this.selecting,
    required this.selected,
    required this.onToggleSelected,
    required this.messagesById,
    this.onLongPressSelect,
    this.grouped = false,
    this.narrow = false,
    this.author,
    this.authorUser,
    this.nameColor,
    this.onUserTap,
    this.onUserContextMenu,
    this.editRequest,
    this.rowRegistry,
    this.highlighted = false,
  });

  final AccordMessage message;
  final String channelId;

  /// Where the pane finds a built row's context by message id, to scroll a
  /// "jump to message" target into view. See `_MessagePaneState._jumpTo`.
  final Map<String, BuildContext>? rowRegistry;

  /// Tinted for a moment after a jump landed on this row.
  final bool highlighted;

  /// The pane asks a row to open its inline editor by setting this to the
  /// row's message id (↑ in the empty composer edits your last message).
  final ValueListenable<String?>? editRequest;

  /// Whether this message continues a group from the same author (see
  /// [_isGrouped]). Grouped rows hide the avatar/name/timestamp header and show
  /// the timestamp in the avatar gutter on hover instead.
  final bool grouped;

  /// Whether the row is rendered in a narrow column (the voice channel's chat
  /// panel). An inline hover action bar reserves its full width even while
  /// invisible, which in a ~340px panel would leave the message itself a few
  /// dozen pixels; a narrow row floats the same bar over its top-right corner
  /// instead. Everything else about the row is unchanged.
  final bool narrow;

  /// Whether the current user can pin/unpin in this channel.
  final bool canManageMessages;

  /// Starts a reply to this message (sets the composer's reply target).
  final VoidCallback onReply;

  /// The space this message belongs to, for opening the author's profile
  /// popout. `null` in contexts without a space (e.g. DMs), which use
  /// [onUserTap]/[onUserContextMenu] instead.
  final String? spaceId;

  /// Whether this message belongs to the current user (gates edit/delete).
  final bool isOwn;

  /// Whether the current user is mentioned by this message (drives highlight).
  final bool mentionsMe;

  /// Whether the pane is in bulk-select mode. While true the row hides its
  /// hover actions, shows a selection checkbox, and a tap toggles selection.
  final bool selecting;

  /// Whether this message is currently selected for bulk deletion.
  final bool selected;

  /// Toggles this message's selection (used while [selecting]).
  final VoidCallback onToggleSelected;

  /// The channel's loaded messages by id, built once per pane build, so the
  /// reply preview finds its target without scanning the list per row.
  final Map<String, AccordMessage> messagesById;

  /// Enters bulk-select mode with this message selected. Null when the current
  /// user lacks `manage_messages` (long-press then does nothing).
  final VoidCallback? onLongPressSelect;

  /// The resolved member for [AccordMessage.authorId], if the space's member
  /// cache has loaded. `null` falls back to [authorUser], then the raw ID.
  final AccordMember? author;

  /// The author resolved from the on-demand user cache, used when the author
  /// isn't in the space's loaded member page. `null` falls back to the raw ID.
  final AccordUser? authorUser;

  /// The author's highest colored-role color, or null for the default color.
  final Color? nameColor;

  /// Account-level user interactions used by DM panes, where no space member
  /// popout exists. Space rows continue to use the member popout directly.
  final ValueChanged<AccordUser>? onUserTap;
  final void Function(AccordUser user, Offset? globalPosition)?
  onUserContextMenu;

  @override
  ConsumerState<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends ConsumerState<_MessageRow>
    with _MessageRowEditing, _MessageRowHandlers, _MessageRowParts {
  /// Hover drives only the action bar and the gutter clock. It is a notifier,
  /// not state: rebuilding the whole row on every hover change rebuilt the
  /// selectable text, which drops its selection and closes the Copy menu the
  /// moment the pointer moves from the text onto that menu.
  final _hover = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    widget.editRequest?.addListener(_onEditRequest);
    widget.rowRegistry?[widget.message.id] = context;
  }

  @override
  void didUpdateWidget(_MessageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editRequest != widget.editRequest) {
      oldWidget.editRequest?.removeListener(_onEditRequest);
      widget.editRequest?.addListener(_onEditRequest);
    }
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.rowRegistry != widget.rowRegistry) {
      _unregister(oldWidget);
      widget.rowRegistry?[widget.message.id] = context;
    }
  }

  void _unregister(_MessageRow of) {
    final registry = of.rowRegistry;
    if (registry != null && identical(registry[of.message.id], context)) {
      registry.remove(of.message.id);
    }
  }

  /// The message this row is currently bound to.
  ///
  /// Only ever read synchronously — during `build`, or at the very top of a
  /// handler. **Never read it after an `await`**: a [State] outlives the widget
  /// it was built from, so while a dialog/picker is open this row can be re-bound
  /// to a different message (the `mounted` guard does not catch that, the State
  /// really is still mounted). Every async handler therefore takes the id it
  /// captured up front. See #198.
  @override
  AccordMessage get _message => widget.message;

  @override
  void dispose() {
    widget.editRequest?.removeListener(_onEditRequest);
    _unregister(widget);
    _hover.dispose();
    _editController?.dispose();
    _editFocus?.dispose();
    super.dispose();
  }

  // Bare HH:MM. Used in the grouped-message gutter, a fixed narrow slot where a
  // full date wouldn't fit (grouped rows are within minutes of their header).
  String get _clock => messageClockFromIso(_message.timestamp);

  // The header time is date-aware so a message from days ago isn't mistaken for
  // a recent one: today shows just the time, yesterday is prefixed, earlier this
  // week shows the weekday, last week is explicitly prefixed, and older messages
  // get the calendar date. intl isn't a dependency, so this is formatted by hand.
  String get _time => messageTimeFromIso(_message.timestamp);

  // Full timestamp shown in the tooltip, e.g. "Monday, 5 June 2026 at 14:30".
  String get _fullTime => messageTimestampFromIso(_message.timestamp);

  /// Nickname → user display name → username → "Unknown". Falls back to the
  /// on-demand user cache when the author isn't in the loaded member page, and
  /// never shows the raw snowflake ID (the user controller fetches asynchronously
  /// — by the next rebuild a real name resolves; "Unknown" is the brief gap).
  @override
  String get _authorName {
    // A webhook call may name itself for one message.
    final webhookName = widget.message.webhookAuthorName;
    if (webhookName != null && webhookName.isNotEmpty) return webhookName;
    if (widget.author != null) {
      return accordMemberName(widget.author, fallback: 'Unknown');
    }
    if (widget.authorUser != null) {
      return accordUserName(widget.authorUser, fallback: 'Unknown');
    }
    return 'Unknown';
  }

  String get _initial => accordInitial(_authorName);

  /// The home domain of a remote (federated) author, or null when local. Drives
  /// the federated-origin badge so remote authors are visually distinguishable.
  String? get _authorOrigin =>
      accordMemberOrigin(widget.author) ??
      accordUserOrigin(widget.authorUser) ??
      _message.origin;

  @override
  AccordClient? get _client => ref.accordClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    // Captured once so every callback this build hands out targets the message
    // that was rendered, never whatever `widget.message` happens to be by the
    // time the callback runs.
    final message = _message;
    // Compact density tightens vertical spacing and shrinks the avatar gutter.
    final compact = ref.watch(
      settingsControllerProvider.select((s) => s.compactMode),
    );
    // Grouped rows sit on their line height alone, as in other chat apps; a
    // fresh author header gets room above and below.
    final topGap = widget.grouped
        ? (compact ? 0.0 : 1.0)
        : (compact ? 3.0 : 6.0);
    final bottomGap = widget.grouped
        ? (compact ? 1.0 : 2.0)
        : (compact ? 3.0 : 6.0);
    final avatarRadius = compact ? 14.0 : 18.0;
    final gutter = compact ? 8.0 : 12.0;
    final cdnUrl = ref.watchCdnUrl();
    // Attachments AutoMod is holding back (or refused) on this message — ours
    // only; the tracker is fed by our own 202s and uploader-only events.
    final pendingUploads = ref.watch(
      pendingUploadsControllerProvider(
        ref.watchActiveServerKey() ?? '',
      ).select((s) => s.forMessage(message.id)),
    );
    final avatarUrl = widget.author != null
        ? accordMemberAvatarUrl(widget.author, cdnUrl)
        : accordAvatarUrl(widget.authorUser, cdnUrl);
    final avatarBg = accordAvatarColor(
      widget.author?.user ?? widget.authorUser,
      message.authorId,
    );
    final tappable =
        widget.spaceId != null ||
        (widget.authorUser != null && widget.onUserTap != null);
    final userMenuEnabled =
        widget.onUserContextMenu != null &&
        (widget.author?.user != null || widget.authorUser != null);
    void openPopout() => _openPopout(message.authorId);
    // Hover actions are mouse-driven and have no affordance on touch, where
    // `Opacity` would still reserve their width and squeeze the message content
    // into a narrow column. Omit them on mobile so the content uses the full
    // row width. On desktop they render inline at the end of the row, or —
    // when [narrow] — floated over it (see [_FloatingActionsOverlay]).
    final showHoverActions =
        !(_editing || widget.selecting || !shouldUseDesktopLayout(context));
    Widget hoverActionsFor(bool hovered) => _HoverActions(
      // Floated (see below), the bar is only built while hovered, so it
      // doesn't need to fade itself out.
      visible: widget.narrow || hovered,
      onReact: () => _openReactionPicker(message.id),
      onReply: widget.onReply,
      onThread: () => _openThread(message),
      canEdit: widget.isOwn,
      canDelete: widget.isOwn || widget.canManageMessages,
      canPin: widget.canManageMessages,
      canReport: !widget.isOwn,
      pinned: message.pinned,
      onEdit: () => _startEdit(message),
      onDelete: () => _delete(message.id),
      onBlock:
          (widget.canManageMessages || ref.readIsAdmin()) &&
              message.attachments.isNotEmpty &&
              (message.spaceId != null || ref.readIsAdmin())
          ? () => _blockFiles(message)
          : null,
      onTogglePin: () => _togglePin(message.id, pinned: message.pinned),
      onReport: () => _report(message),
      onMenuStateChanged: _menuStateChanged,
    );
    return MouseRegion(
      onEnter: (_) => _hover.value = true,
      onExit: (_) => _hover.value = false,
      child: ValueListenableBuilder<bool>(
        valueListenable: _hover,
        builder: (context, hovered, content) => _FloatingActionsOverlay(
          // In the voice chat panel an inline action bar would leave the message
          // a few dozen pixels of width, so the bar floats over the row's
          // top-right corner instead — and only while hovered, so it never covers
          // the text or swallows a click. `_menuOpen` extends that past the
          // hover: the actions menu's barrier ends the hover, and unmounting the
          // button mid-menu loses the selection (see [_menuStateChanged]).
          actions:
              showHoverActions &&
                  widget.narrow &&
                  (hovered || _menuOpen) &&
                  !isEphemeralMessage(message)
              ? hoverActionsFor(hovered)
              : null,
          // A faint highlight under the hovered message. Only this box
          // repaints: the message itself is passed through untouched.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.highlighted
                  ? colors.primary.withValues(alpha: 0.16)
                  : hovered && shouldUseDesktopLayout(context)
                  ? Color.lerp(colors.background, colors.darkGray, 0.18)
                  : Colors.transparent,
            ),
            child: content!,
          ),
        ),
        child: MessageTextMenuScope(
          onContextMenu: (position, copy) {
            if (widget.selecting || isEphemeralMessage(message)) return;
            _showActionsMenu(message, position, copy);
          },
          child: GestureDetector(
            // Opaque so the whole row is hit-testable: on mobile a plain-text
            // message renders as a bare RichText with no recognisers, and the
            // surrounding Container is transparent, so with the default
            // `deferToChild` a long-press over the text hits nothing and never
            // fires. Only the avatar (which paints a background) responded before.
            behavior: HitTestBehavior.opaque,
            onLongPressStart: widget.selecting || isEphemeralMessage(message)
                ? null
                : (d) => _showActionsMenu(message, d.globalPosition),
            onSecondaryTapUp: widget.selecting || isEphemeralMessage(message)
                ? null
                : (d) => _showActionsMenu(message, d.globalPosition),
            onTap: widget.selecting ? widget.onToggleSelected : null,
            child: Container(
              padding: widget.mentionsMe
                  ? EdgeInsets.fromLTRB(13, topGap, 6, bottomGap)
                  : EdgeInsets.only(top: topGap, bottom: bottomGap),
              decoration: widget.selected
                  ? BoxDecoration(color: colors.primary.withValues(alpha: 0.14))
                  : widget.mentionsMe
                  ? BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.08),
                      border: Border(
                        left: BorderSide(color: colors.primary, width: 3),
                      ),
                    )
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.selecting) ...[
                    Checkbox(
                      value: widget.selected,
                      onChanged: (_) => widget.onToggleSelected(),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (widget.grouped)
                    ValueListenableBuilder<bool>(
                      valueListenable: _hover,
                      builder: (_, hovered, _) => _GutterTimestamp(
                        width: avatarRadius * 2,
                        visible: hovered,
                        clock: _clock,
                        fullTime: _fullTime,
                      ),
                    )
                  else
                    _MaybeTappable(
                      enabled: tappable,
                      onTap: openPopout,
                      onLongPressStart: userMenuEnabled
                          ? (d) => _openUserMenu(d.globalPosition)
                          : null,
                      onSecondaryTapUp: userMenuEnabled
                          ? (d) => _openUserMenu(d.globalPosition)
                          : null,
                      child: AccordMemberAvatar(
                        avatarUrl: avatarUrl,
                        initial: _initial,
                        radius: avatarRadius,
                        backgroundColor: avatarBg,
                        initialStyle: theme.textTheme.titleSmall,
                      ),
                    ),
                  SizedBox(width: gutter),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.spaceId == null && message.type == 'default')
                          Text(
                            message.isEncrypted
                                ? (message.encryptionError == null
                                      ? 'End-to-end encrypted'
                                      : 'Encryption could not be verified')
                                : 'Unencrypted history',
                            style: theme.textTheme.labelSmall,
                          ),
                        if (message.replyTo != null)
                          _buildReplyPreview(message, colors),
                        if (message.interaction case final interaction?)
                          MessageInteractionHeader(
                            interaction: interaction,
                            serverKey: ref.readActiveServerKey() ?? '',
                            spaceId: widget.spaceId,
                          ),
                        if (!widget.grouped)
                          MessageAuthorHeader(
                            name: _authorName,
                            nameColor: widget.nameColor,
                            // A long name must ellipsize rather than push the
                            // timestamp out of a narrow row.
                            ellipsizeName: true,
                            onNameTap: tappable ? openPopout : null,
                            onNameLongPressStart: userMenuEnabled
                                ? (d) => _openUserMenu(d.globalPosition)
                                : null,
                            onNameSecondaryTapUp: userMenuEnabled
                                ? (d) => _openUserMenu(d.globalPosition)
                                : null,
                            pinned: message.pinned,
                            origin: _authorOrigin,
                            time: _time,
                            timeTooltip: _fullTime,
                            edited: message.editedAt != null,
                            appBadge:
                                message.webhookId != null ||
                                (widget.author?.user?.bot ??
                                    widget.authorUser?.bot ??
                                    false),
                          ),
                        if (_editing)
                          _buildEditor(theme, colors)
                        else if (isLoadingMessage(message))
                          MessageThinking(botName: _authorName)
                        else if (isSystemMessage(message) ||
                            message.content.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: MessageBody(
                              message: message,
                              authorName: _authorName,
                              spaceId: widget.spaceId,
                            ),
                          ),
                        if (message.poll case final poll?)
                          PollView(
                            poll: poll,
                            onVote: (answerId, {required remove}) =>
                                _votePoll(message.id, answerId, remove: remove),
                          ),
                        for (final sticker in message.stickers)
                          MessageSticker(sticker: sticker),
                        for (final attachment in message.attachments)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _buildAttachment(attachment, cdnUrl, theme),
                          ),
                        for (final upload in pendingUploads)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: _PendingAttachmentTile(upload: upload),
                          ),
                        if (ref.watch(
                              settingsControllerProvider.select(
                                (s) => s.showEmbeds,
                              ),
                            ) &&
                            (message.flags & (1 << 2)) == 0)
                          for (final embed in message.embeds)
                            AccordEmbedBox(embed: embed, cdnUrl: cdnUrl),
                        if (message.components != null)
                          MessageComponentsView(message: message),
                        if (isEphemeralMessage(message))
                          EphemeralFooter(
                            onDismiss: () => ref
                                .read(
                                  accordMessagesControllerProvider(
                                    ref.readActiveServerKey() ?? '',
                                    widget.channelId,
                                  ).notifier,
                                )
                                .removeMessage(message.id),
                          ),
                        if ((message.reactions ?? const []).isNotEmpty ||
                            message.superReactions.isNotEmpty)
                          _buildReactions(message, theme, colors, cdnUrl),
                        if (message.replyCount > 0)
                          _buildThreadChip(message, theme, colors),
                      ],
                    ),
                  ),
                  if (showHoverActions && !widget.narrow)
                    ValueListenableBuilder<bool>(
                      valueListenable: _hover,
                      builder: (_, hovered, _) => hoverActionsFor(hovered),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  AccordMessagesController? get _channelMessages {
    final serverKey = ref.readActiveServerKey();
    if (serverKey == null) return null;
    return ref.read(
      accordMessagesControllerProvider(serverKey, widget.channelId).notifier,
    );
  }
}
