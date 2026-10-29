part of 'accord_direct_messages.dart';

class _DmListTab extends ConsumerStatefulWidget {
  const _DmListTab({required this.selfId, required this.onOpen});

  final String? selfId;
  final ValueChanged<AccordChannel> onOpen;

  @override
  ConsumerState<_DmListTab> createState() => _DmListTabState();
}

class _DmListTabState extends ConsumerState<_DmListTab> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  AccordClient? get _client => ref.accordClient;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = _client;
    final serverKey = ref.readActiveServerKey();
    if (client == null || serverKey == null) return;
    final result = await client.users.listChannels();
    if (!mounted || ref.readActiveServerKey() != serverKey) return;
    final data = result.data;
    final channels = data is List
        ? data.whereType<AccordChannel>().toList()
        : <AccordChannel>[];
    final controller = ref.read(
      dmChannelsControllerProvider(serverKey).notifier,
    );
    controller.setChannels(channels);
    await Future.wait([
      for (final channel in channels)
        client.messages.list(channel.id, query: {'limit': 1}).then((result) {
          if (!mounted || ref.readActiveServerKey() != serverKey) return;
          final messages = result.data;
          if (result.ok && messages is List) {
            AccordMessage? latest;
            for (final message in messages.whereType<AccordMessage>()) {
              latest = message;
              break;
            }
            if (latest != null) controller.setPreview(channel.id, latest);
          }
        }),
    ]);
  }

  Future<void> _createGroup() async {
    final serverKey = ref.readActiveServerKey();
    final channel = await showDialog<AccordChannel>(
      context: context,
      builder: (_) => const _CreateGroupDialog(),
    );
    if (channel == null ||
        !mounted ||
        serverKey == null ||
        ref.readActiveServerKey() != serverKey) {
      return;
    }
    // Surface the new group immediately; the gateway channel.create echo (and
    // the next _load) keep the cache authoritative.
    ref.read(dmChannelsControllerProvider(serverKey).notifier).upsert(channel);
    widget.onOpen(channel);
  }

  /// Prompts for a remote user's qualified handle (`<id>@<domain>`) and opens a
  /// cross-server DM with them. The opened channel is reflected in the DM list
  /// (and surfaced) by [openAccordDirectMessage].
  Future<void> _messageRemoteUser() async {
    final handle = await showDialog<String>(
      context: context,
      builder: (_) => const _RemoteDmDialog(),
    );
    if (handle == null || !mounted) return;
    await openAccordDirectMessage(context, ref, handle);
  }

  Future<void> _closeConversation(AccordChannel channel) async {
    final group = _isGroup(channel, widget.selfId);
    final confirmed = await showConfirmDialog(
      context,
      title: group ? 'Leave group' : 'Close direct message',
      message: group
          ? 'Leave ${_channelTitle(channel, widget.selfId)}? You can be re-added later.'
          : 'Remove this conversation from your direct-message list? Its history is retained if you message this user again.',
      confirmLabel: group ? 'Leave' : 'Close',
      danger: true,
    );
    if (confirmed != true || !mounted) return;
    final client = _client;
    final serverKey = ref.readActiveServerKey();
    if (client == null || serverKey == null) return;
    final selfId = widget.selfId;
    if (group && selfId == null) return;
    final result = group
        ? await client.channels.removeRecipient(channel.id, selfId!)
        : await client.channels.delete(channel.id);
    if (!mounted || ref.readActiveServerKey() != serverKey) return;
    if (!result.ok) {
      showInfoSnack(
        context,
        result.errorMessageOr(
          group ? 'Failed to leave group' : 'Failed to close conversation',
        ),
      );
      return;
    }
    ref
        .read(dmChannelsControllerProvider(serverKey).notifier)
        .remove(channel.id);
    ref
        .read(readStateControllerProvider(serverKey).notifier)
        .markRead(channel.id);
  }

  void _showConversationMenu(AccordChannel channel, Offset? position) {
    final group = _isGroup(channel, widget.selfId);
    final others = _others(channel, widget.selfId);
    final user = !group && others.isNotEmpty ? others.first : null;
    final closeEntry = AccordMenuEntry(
      label: group ? 'Leave group' : 'Close direct message',
      icon: group ? Icons.logout : Icons.close,
      destructive: true,
      onSelected: () => _closeConversation(channel),
    );
    if (user != null) {
      showAccordDmUserContextMenu(
        context,
        ref,
        user,
        globalPosition: position,
        currentDmUserId: user.id,
        extraEntries: [const AccordMenuEntry.divider(), closeEntry],
      );
      return;
    }
    showAccordContextMenu(
      context,
      entries: [closeEntry],
      globalPosition: position,
      title: _channelTitle(channel, widget.selfId),
      titleIcon: Icons.group_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final channels = ref.watch(dmChannelsControllerProvider(serverKey));
    final previews = ref.read(dmChannelsControllerProvider(serverKey).notifier);
    final cdnUrl = ref.watchCdnUrl();
    final missed = ref.watch(missedCallsControllerProvider);
    final presences = ref.watch(activePresencesProvider);
    final readState = ref.watch(readStateControllerProvider(serverKey));
    final channelLevels = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.channelNotificationsFor(serverKey),
      ),
    );
    final query = _search.text.trim().toLowerCase();
    final filtered = channels
        ?.where(
          (channel) =>
              query.isEmpty ||
              _channelTitle(
                channel,
                widget.selfId,
              ).toLowerCase().contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: colors.background,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Search conversations',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'New group',
                onPressed: _createGroup,
                icon: Icon(Icons.group_add_outlined, color: colors.dirtyWhite),
              ),
              IconButton(
                tooltip: 'Message remote user',
                onPressed: _messageRemoteUser,
                icon: Icon(Icons.alternate_email, color: colors.dirtyWhite),
              ),
            ],
          ),
        ),
        Expanded(
          child: channels == null
              ? const LoadingView()
              : filtered!.isEmpty
              ? Center(
                  child: Text(
                    query.isEmpty
                        ? 'No direct messages yet'
                        : 'No matching conversations',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final channel = filtered[index];
                    final group = _isGroup(channel, widget.selfId);
                    final others = _others(channel, widget.selfId);
                    final other = group || others.isEmpty ? null : others.first;
                    final previewAuthor = previews.previewAuthorFor(channel.id);
                    final tile = _DmConversationTile(
                      title: _channelTitle(channel, widget.selfId),
                      group: group,
                      avatarId: other?.id ?? channel.id,
                      avatarUrl: other == null
                          ? null
                          : accordAvatarUrl(other, cdnUrl),
                      status: other == null
                          ? null
                          : accordPresenceStatus(presences, other.id),
                      origin: _dmRemoteOrigin(channel, widget.selfId),
                      preview: previews.previewFor(channel.id),
                      previewIsOwn:
                          previewAuthor != null &&
                          previewAuthor == widget.selfId,
                      sentAt: previews.previewTimeFor(channel.id),
                      memberCount: others.length + 1,
                      missedCall: missed[channel.id],
                      unread: readState.isUnreadVisible(
                        channel.id,
                        channelLevels: channelLevels,
                      ),
                      mentions: readState.visibleMentionCount(
                        channel.id,
                        channelLevels: channelLevels,
                      ),
                      onTap: () => widget.onOpen(channel),
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPressStart: (details) => _showConversationMenu(
                        channel,
                        details.globalPosition,
                      ),
                      onSecondaryTapUp: (details) => _showConversationMenu(
                        channel,
                        details.globalPosition,
                      ),
                      child: tile,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// One row of the DM list: a large avatar with presence, the conversation title
/// with its last-activity time, and the last-message preview with any unread
/// or mention indicator. Unread rows are emphasised by weight and colour rather
/// than a background fill, so the list reads cleanly at a glance.
class _DmConversationTile extends StatelessWidget {
  const _DmConversationTile({
    required this.title,
    required this.group,
    required this.avatarId,
    required this.avatarUrl,
    required this.status,
    required this.origin,
    required this.preview,
    required this.previewIsOwn,
    required this.sentAt,
    required this.memberCount,
    required this.missedCall,
    required this.unread,
    required this.mentions,
    required this.onTap,
  });

  final String title;
  final bool group;

  /// Seeds the fallback avatar colour: the other user for a 1:1 DM, the
  /// channel for a group.
  final String avatarId;
  final String? avatarUrl;
  final String? status;
  final String? origin;
  final String? preview;
  final bool previewIsOwn;
  final DateTime? sentAt;
  final int memberCount;
  final MissedCall? missedCall;
  final bool unread;
  final int mentions;
  final VoidCallback onTap;

  static const double _avatarRadius = 24;

  /// Below this title width the origin badge shows its globe only.
  static const double _originDomainMinWidth = 240;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final emphasised = unread || mentions > 0;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontSize: 16,
      fontWeight: emphasised ? FontWeight.w700 : FontWeight.w600,
      color: emphasised
          ? colors.dirtyWhite
          : colors.dirtyWhite.withValues(alpha: 0.9),
    );
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: emphasised ? colors.primary : colors.gray,
      fontWeight: emphasised ? FontWeight.w600 : null,
    );
    final previewStyle = theme.textTheme.bodyMedium?.copyWith(
      color: emphasised ? colors.dirtyWhite : colors.gray,
      fontWeight: emphasised ? FontWeight.w500 : null,
    );
    final sentAt = this.sentAt;
    final missedCall = this.missedCall;
    final preview = this.preview;

    final Widget? subtitle = missedCall != null
        ? _MissedCallLabel(missed: missedCall)
        : preview != null
        ? Text(
            previewIsOwn ? 'You: $preview' : preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: previewStyle,
          )
        : group
        ? Text('$memberCount members', style: previewStyle)
        : null;

    final Widget? indicator = mentions > 0
        ? Badge(label: Text('$mentions'), backgroundColor: colors.red)
        : unread || missedCall != null
        ? Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: missedCall != null ? colors.red : colors.primary,
              shape: BoxShape.circle,
            ),
          )
        : null;

    // Unread, mentions and presence are drawn as weight, colour and dots, which
    // a screen reader can't see: announce the row as one sentence instead of
    // its separate fragments. MergeSemantics keeps the InkWell's tap and focus
    // actions on that same node.
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Semantics(
            button: true,
            label: _semanticsLabel(),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(
                children: [
                  group
                      ? CircleAvatar(
                          radius: _avatarRadius,
                          backgroundColor: accordIdColor(avatarId),
                          child: Icon(
                            Icons.group,
                            size: 22,
                            color: accordOnColor(accordIdColor(avatarId)),
                          ),
                        )
                      : AccordMemberAvatar(
                          avatarUrl: avatarUrl,
                          initial: accordInitial(title),
                          status: status,
                          radius: _avatarRadius,
                          backgroundColor: accordIdColor(avatarId),
                          initialStyle: theme.textTheme.titleMedium,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            // The title (and its origin badge) take all the width
                            // the time label leaves, so long names only truncate
                            // when they really run into it. On a narrow row the
                            // badge drops its "@domain" text for the globe alone
                            // (its tooltip and the row semantics keep the domain)
                            // so it can't crowd the name out or overflow.
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) => Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: titleStyle,
                                      ),
                                    ),
                                    if (origin != null) ...[
                                      const SizedBox(width: 6),
                                      RemoteOriginBadge(
                                        domain: origin!,
                                        showDomain:
                                            constraints.maxWidth >=
                                            _originDomainMinWidth,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (sentAt != null) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: messageTimestampString(sentAt),
                                child: Text(
                                  conversationTimeString(sentAt),
                                  style: metaStyle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (subtitle != null || indicator != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: subtitle ?? const SizedBox.shrink(),
                              ),
                              if (indicator != null) ...[
                                const SizedBox(width: 8),
                                indicator,
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The row read as one phrase, e.g. "bob, online, Unread, 2 mentions,
  /// You: see you there, Sun, 27 Sep 2026 at 12:30".
  String _semanticsLabel() {
    final status = this.status;
    final origin = this.origin;
    final preview = this.preview;
    final sentAt = this.sentAt;
    final missedCall = this.missedCall;
    return [
      title,
      if (origin != null && origin.isNotEmpty) 'homed on $origin',
      if (group) 'group' else if (status != null) _presenceLabel(status),
      if (unread || mentions > 0) 'Unread',
      if (mentions == 1)
        '1 mention'
      else if (mentions > 1)
        '$mentions mentions',
      if (missedCall != null)
        missedCall.label
      else if (preview != null)
        previewIsOwn ? 'You: $preview' : preview
      else if (group)
        '$memberCount members',
      if (sentAt != null) messageTimestampString(sentAt),
    ].join(', ');
  }

  static String _presenceLabel(String status) => switch (status) {
    'online' => 'online',
    'idle' => 'idle',
    'dnd' => 'do not disturb',
    _ => 'offline',
  };
}

/// The "Missed call" line under a DM row: an unanswered incoming call the user
/// hasn't opened the conversation for yet. Cleared by opening the conversation.
class _MissedCallLabel extends StatelessWidget {
  const _MissedCallLabel({required this.missed});

  final MissedCall missed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: colors.red,
      fontWeight: FontWeight.w600,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          missed.video ? Icons.missed_video_call : Icons.call_missed,
          size: 14,
          color: colors.red,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            missed.label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
