part of '../thread_view.dart';

/// An author + content row used inside the thread view, with an actions menu
/// (edit/delete/copy) mirroring the main message view. The root post and
/// replies share this; [isRoot] only changes the edit affordance (title-aware)
/// and routes edit/delete to the [onEdit]/[onDelete] callbacks instead of the
/// replies controller. Reply mutations go straight to
/// [ThreadRepliesController] (addressed by [channelId] + [rootId]).
class _MessageLine extends ConsumerStatefulWidget {
  const _MessageLine({
    super.key,
    required this.message,
    required this.isRoot,
    required this.spaceId,
    required this.channelId,
    required this.rootId,
    required this.isOwn,
    required this.canManageMessages,
    this.onUserTap,
    this.onUserContextMenu,
    this.onEdit,
    this.onDelete,
  });

  final AccordMessage message;
  final bool isRoot;
  final String? spaceId;
  final String channelId;

  /// The thread's root message id — the replies-controller family key.
  final String rootId;
  final bool isOwn;
  final bool canManageMessages;
  final ValueChanged<AccordUser>? onUserTap;
  final void Function(AccordUser user, Offset? globalPosition)?
  onUserContextMenu;

  /// Root-only handlers (the root edits its title and pops on delete).
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_MessageLine> createState() => _MessageLineState();
}

class _MessageLineState extends ConsumerState<_MessageLine> {
  bool _hovered = false;
  bool _busy = false;

  /// The message this row is currently bound to. Only safe to read
  /// synchronously — never after an `await`, since the State can be re-bound to
  /// a different reply while a dialog is open (see #198). Async handlers take
  /// the message they captured up front instead.
  AccordMessage get _message => widget.message;

  AccordClient? get _client => ref.accordClient;

  ThreadRepliesController get _replies => ref.read(
    threadRepliesControllerProvider(
      ref.readActiveServerKey() ?? '',
      widget.channelId,
      widget.rootId,
    ).notifier,
  );

  bool get _canDelete => widget.isOwn || widget.canManageMessages;

  String get _time => messageTimeFromIso(_message.timestamp);

  Future<void> _edit(AccordMessage message) async {
    if (widget.isRoot) {
      widget.onEdit?.call();
      return;
    }
    final updated = await showPostEditor(
      context,
      channelId: widget.channelId,
      post: message,
      withTitle: false,
    );
    if (updated != null && mounted) _replies.updateReply(updated);
  }

  Future<void> _delete(String messageId) async {
    if (widget.isRoot) {
      widget.onDelete?.call();
      return;
    }
    final client = _client;
    if (client == null || _busy) return;
    final confirmed = await confirmDeletePost(context, isPost: false);
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await _replies.delete(client, messageId);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  /// [message] is captured when the menu opens: its entries only run once the
  /// menu has closed, by which point this row may be bound to another reply.
  void _showMenu(AccordMessage message, [Offset? position]) {
    final authorId = message.authorId;
    final member = widget.spaceId == null
        ? null
        : ref.read(
            accordMembersControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId!,
            ),
          )?[authorId];
    final user = ref.read(
      accordUsersControllerProvider(ref.readActiveServerKey() ?? ''),
    )[authorId];
    final name = accordAuthorNameOf(authorId, member: member, user: user);
    final entries = [
      ...buildMessageActionEntries(
        content: accordMessageText(message, authorName: name),
        canEdit: widget.isOwn,
        canDelete: _canDelete,
        onEdit: () => _edit(message),
        onDelete: () => _delete(message.id),
      ),
      // A reply is a message like any other: it can be flagged here too, so no
      // message surface is left without the action (#290).
      if (!widget.isOwn)
        AccordMenuEntry(
          label: 'Report',
          icon: Icons.flag_outlined,
          onSelected: () => showReportDialog(
            context,
            spaceId: widget.spaceId,
            targetType: 'message',
            targetId: message.id,
            channelId: widget.channelId,
            reportedUserId: authorId.isEmpty ? null : authorId,
            reportedName: name,
          ),
        ),
    ];
    if (entries.isEmpty) return;
    showAccordContextMenu(
      context,
      entries: entries,
      globalPosition: position,
      title: name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Captured once so the callbacks handed out by this build target the
    // message that was rendered.
    final message = _message;
    // Per-row identity lookups, scoped to this author: watching just the one
    // cache entry means a change to an unrelated member/user doesn't rebuild
    // every row in the thread.
    final authorId = message.authorId;
    final member = widget.spaceId == null
        ? null
        : ref.watch(
            accordMembersControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId!,
            ).select((m) => m?[authorId]),
          );
    final user = ref.watch(
      accordUsersControllerProvider(
        ref.readActiveServerKey() ?? '',
      ).select((m) => m[authorId]),
    );
    final ensure = ref
        .read(
          accordUsersControllerProvider(
            ref.readActiveServerKey() ?? '',
          ).notifier,
        )
        .ensure;
    final cdnUrl = ref.watchCdnUrl();
    final name = accordAuthorNameOf(
      authorId,
      member: member,
      user: user,
      ensure: ensure,
    );
    final avatarUrl = accordAuthorAvatarUrlOf(
      member: member,
      user: user,
      cdnUrl: cdnUrl,
    );
    final avatarBg = accordAvatarColor(member?.user ?? user, authorId);
    final initial = accordInitial(name);
    final author = member?.user ?? user;
    final userActionsEnabled =
        author != null &&
        (widget.onUserTap != null || widget.onUserContextMenu != null);
    void openUser() {
      if (author != null) widget.onUserTap?.call(author);
    }

    void openUserMenu(Offset? position) {
      if (author != null) widget.onUserContextMenu?.call(author, position);
    }

    Widget avatar = AccordMemberAvatar(
      avatarUrl: avatarUrl,
      initial: initial,
      backgroundColor: avatarBg,
      radius: 16,
    );
    if (userActionsEnabled) {
      avatar = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onUserTap == null ? null : openUser,
          onLongPressStart: widget.onUserContextMenu == null
              ? null
              : (details) => openUserMenu(details.globalPosition),
          onSecondaryTapUp: widget.onUserContextMenu == null
              ? null
              : (details) => openUserMenu(details.globalPosition),
          child: avatar,
        ),
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // Opaque so a long-press anywhere on the row (not just the avatar)
        // opens the menu; plain-text content is a transparent RichText that
        // wouldn't register a hit under the default `deferToChild`.
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (d) => _showMenu(message, d.globalPosition),
        onSecondaryTapUp: (d) => _showMenu(message, d.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MessageAuthorHeader(
                      name: name,
                      ellipsizeName: true,
                      onNameTap: userActionsEnabled && widget.onUserTap != null
                          ? openUser
                          : null,
                      onNameLongPressStart:
                          userActionsEnabled && widget.onUserContextMenu != null
                          ? (details) => openUserMenu(details.globalPosition)
                          : null,
                      onNameSecondaryTapUp:
                          userActionsEnabled && widget.onUserContextMenu != null
                          ? (details) => openUserMenu(details.globalPosition)
                          : null,
                      time: _time,
                      smallTime: true,
                      edited: message.editedAt != null,
                    ),
                    const SizedBox(height: 2),
                    if (message.type == 'member_join' ||
                        message.content.isNotEmpty)
                      MessageBody(
                        message: message,
                        authorName: name,
                        spaceId: widget.spaceId,
                      ),
                  ],
                ),
              ),
              // Shown for someone else's reply too — that menu now carries the
              // Report action, which must not be long-press-only (#290).
              if (_canDelete || !widget.isOwn)
                Opacity(
                  opacity: _hovered ? 1 : 0,
                  child: IconButton(
                    tooltip: 'Actions',
                    onPressed: _busy ? null : () => _showMenu(message),
                    icon: Icon(Icons.more_horiz, size: 18, color: colors.gray),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
