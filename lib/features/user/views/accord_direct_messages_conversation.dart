part of 'accord_direct_messages.dart';

class _DmConversation extends ConsumerStatefulWidget {
  const _DmConversation({
    required this.channel,
    required this.selfId,
    required this.onBack,
  });

  final AccordChannel channel;
  final String? selfId;
  final VoidCallback onBack;

  @override
  ConsumerState<_DmConversation> createState() => _DmConversationState();
}

class _DmConversationState extends ConsumerState<_DmConversation> {
  late AccordChannel _channel = widget.channel;
  late final String _serverKey = ref.readActiveServerKey() ?? '';
  ServerChannelKey? _previousVisibleChannel;

  @override
  void initState() {
    super.initState();
    _previousVisibleChannel = accordVisibleChannel;
    // Opening the conversation is the acknowledgement: drop any missed-call
    // indicator for it. Deferred a frame — `initState` runs during a build, and
    // Riverpod forbids mutating a provider from inside one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final user in _channel.recipients ?? const <AccordUser>[]) {
        ref
            .read(accordUsersControllerProvider(_serverKey).notifier)
            .upsert(user);
      }
      accordVisibleChannel = (serverKey: _serverKey, channelId: _channel.id);
      markChannelRead(
        ref,
        _channel.id,
        serverKey: _serverKey,
        fallbackMessageId: _channel.lastMessageId,
      );
      ref.read(missedCallsControllerProvider.notifier).clear(_channel.id);
    });
  }

  @override
  void dispose() {
    final visible = accordVisibleChannel;
    if (visible?.serverKey == _serverKey && visible?.channelId == _channel.id) {
      accordVisibleChannel = _previousVisibleChannel;
    }
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  bool get _isGroupChannel => _isGroup(_channel, widget.selfId);

  bool get _isOwner =>
      _channel.ownerId != null && _channel.ownerId == widget.selfId;

  /// Updates the local channel and mirrors it into the shared DM cache so the
  /// list behind this conversation reflects the change too.
  void _setChannel(AccordChannel channel) {
    setState(() => _channel = channel);
    ref
        .read(
          dmChannelsControllerProvider(
            ref.readActiveServerKey() ?? '',
          ).notifier,
        )
        .upsert(channel);
  }

  /// Refetches the channel so the recipient list reflects add/remove changes.
  Future<void> _refreshChannel() async {
    final client = _client;
    if (client == null) return;
    final result = await client.channels.fetch(_channel.id);
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is AccordChannel) {
      _setChannel(data);
    }
  }

  Future<void> _addMember() async {
    final user = await showDialog<AccordUser>(
      context: context,
      builder: (_) => _PickUserDialog(
        title: 'Add to group',
        excludeIds: {
          if (widget.selfId != null) widget.selfId!,
          ..._others(_channel, widget.selfId).map((u) => u.id),
        },
      ),
    );
    if (user == null) return;
    final client = _client;
    if (client == null) return;
    final result = await client.channels.addRecipient(_channel.id, user.id);
    if (!mounted) return;
    if (result.ok) {
      await _refreshChannel();
    } else {
      showInfoSnack(context, 'Failed to add member');
    }
  }

  Future<void> _removeMember(AccordUser user) async {
    final client = _client;
    if (client == null) return;
    final ok = await _confirm(
      'Remove member',
      'Remove ${_userName(user)} from this group?',
      'Remove',
    );
    if (ok != true) return;
    final result = await client.channels.removeRecipient(_channel.id, user.id);
    if (!mounted) return;
    if (result.ok) {
      await _refreshChannel();
    } else {
      showInfoSnack(context, 'Failed to remove member');
    }
  }

  Future<void> _rename() async {
    final name = await showTextPromptDialog(
      context,
      title: 'Rename group',
      label: 'Group name',
      initial: _channel.name ?? '',
    );
    if (name == null) return;
    final client = _client;
    if (client == null) return;
    final result = await client.channels.update(_channel.id, {
      'name': name.trim(),
    });
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is AccordChannel) {
      _setChannel(data);
    } else if (result.ok) {
      await _refreshChannel();
    } else {
      showInfoSnack(context, 'Failed to rename group');
    }
  }

  Future<void> _leave() async {
    final selfId = widget.selfId;
    final client = _client;
    if (client == null || selfId == null) return;
    final ok = await _confirm(
      'Leave group',
      'Leave this group? You can be re-added later.',
      'Leave',
    );
    if (ok != true) return;
    final result = await client.channels.removeRecipient(_channel.id, selfId);
    if (!mounted) return;
    if (result.ok) {
      ref
          .read(
            dmChannelsControllerProvider(
              ref.readActiveServerKey() ?? '',
            ).notifier,
          )
          .remove(_channel.id);
      widget.onBack();
    } else {
      showInfoSnack(context, 'Failed to leave group');
    }
  }

  Future<bool?> _confirm(String title, String message, String action) {
    return showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: action,
    );
  }

  /// Places an outgoing DM call: rings the other participant(s) and opens the
  /// full-screen call view. The callee gets a `call.ring` and can accept/decline.
  Future<void> _startCall({required bool video}) async {
    // The app's root navigator is go_router's (see `buildAppShell`): the call
    // view goes above this dialog, under the incoming-call banner host.
    final navigator = Navigator.of(context, rootNavigator: true);
    await ref
        .read(callControllerProvider.notifier)
        .startCall(_channel, video: video);
    if (!mounted) return;
    // Bail if the underlying voice join failed. The voice bar shows the error
    // too, but it isn't on screen behind this dialog — say it here, where the
    // call was placed, rather than silently doing nothing (#324).
    if (ref.read(voiceControllerProvider).channelId != _channel.id) {
      final error = ref.read(voiceControllerProvider).error;
      if (error != null) showInfoSnack(context, error);
      return;
    }
    await showFullScreenVoice(
      navigator.context,
      channelId: _channel.id,
      spaceId: null,
      channelName: _channelTitle(_channel, widget.selfId),
    );
  }

  void _showMembers() {
    showDialog<void>(
      context: context,
      builder: (_) => _GroupMembersDialog(
        members: _others(_channel, widget.selfId),
        canRemove: _isOwner,
        onRemove: (u) {
          Navigator.of(context).pop();
          _removeMember(u);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // Keep the open conversation in sync with gateway-driven channel updates
    // (remote rename / recipient add/remove) the DM cache receives.
    ref.listen<List<AccordChannel>?>(
      dmChannelsControllerProvider(ref.readActiveServerKey() ?? ''),
      (previous, next) {
        if (next == null) return;
        AccordChannel? updated;
        for (final c in next) {
          if (c.id == _channel.id) {
            updated = c;
            break;
          }
        }
        if (updated != null && !identical(updated, _channel)) {
          setState(() => _channel = updated!);
        }
      },
    );
    // The home route remains mounted beneath this dialog and may rebuild while
    // it is open. Reassert the modal conversation as the visible channel so its
    // incoming messages do not produce unread badges/notifications.
    accordVisibleChannel = (serverKey: _serverKey, channelId: _channel.id);
    final group = _isGroupChannel;
    final others = _others(_channel, widget.selfId);
    final directUser = group || others.isEmpty ? null : others.first;
    final title = _channelTitle(_channel, widget.selfId);
    final origin = _dmRemoteOrigin(_channel, widget.selfId);
    return MessagePane(
      channel: _channel,
      channelId: _channel.id,
      spaceId: null,
      composerTitle: title,
      canManageMessagesOverride: true,
      headerLeading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: widget.onBack,
            icon: Icon(Icons.arrow_back, size: 20, color: colors.dirtyWhite),
          ),
          if (group)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: colors.darkGray,
                child: Icon(Icons.group, size: 16, color: colors.dirtyWhite),
              ),
            )
          else if (directUser != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _DmUserGesture(
                user: directUser,
                onTap: () => _showUserProfile(directUser),
                onMenu: (position) => _showUserMenu(directUser, position),
                child: UserAvatar(
                  title,
                  imageUrl: accordAvatarUrl(directUser, ref.watchCdnUrl()),
                  radius: 14,
                ),
              ),
            ),
        ],
      ),
      headerTitle: _DmHeaderTitle(
        title: title,
        origin: origin,
        onTap: directUser == null ? null : () => _showUserProfile(directUser),
        onMenu: directUser == null
            ? null
            : (position) => _showUserMenu(directUser, position),
      ),
      headerActions: [
        IconButton(
          tooltip: 'Start voice call',
          onPressed: () => _startCall(video: false),
          icon: Icon(Icons.call, size: 20, color: colors.dirtyWhite),
        ),
        IconButton(
          tooltip: 'Start video call',
          onPressed: () => _startCall(video: true),
          icon: Icon(Icons.videocam, size: 20, color: colors.dirtyWhite),
        ),
        if (group)
          _groupOptions(colors)
        // The 1:1 menu (report, block, friend actions) otherwise only opened on
        // long-press / right-click, which leaves nothing to find by tapping
        // around a DM (App Review 1.2, #290).
        else if (directUser != null)
          IconButton(
            tooltip: 'Conversation options',
            onPressed: () => _showUserMenu(directUser),
            icon: Icon(Icons.more_vert, size: 20, color: colors.gray),
          ),
      ],
      onUserTap: _showUserProfile,
      onUserContextMenu: _showUserMenu,
    );
  }

  void _showUserProfile(AccordUser user) {
    showAccordUserProfile(context, user, cdnUrl: ref.readCdnUrl());
  }

  void _showUserMenu(AccordUser user, [Offset? position]) {
    final others = _others(_channel, widget.selfId);
    showAccordDmUserContextMenu(
      context,
      ref,
      user,
      globalPosition: position,
      currentDmUserId: others.length == 1 ? others.first.id : null,
    );
  }

  Widget _groupOptions(BonfireThemeExtension colors) => PopupMenuButton<String>(
    tooltip: 'Group options',
    icon: Icon(Icons.more_vert, size: 20, color: colors.gray),
    onSelected: (value) {
      switch (value) {
        case 'members':
          _showMembers();
        case 'add':
          _addMember();
        case 'rename':
          _rename();
        case 'leave':
          _leave();
      }
    },
    itemBuilder: (context) => [
      const PopupMenuItem(value: 'members', child: Text('View members')),
      const PopupMenuItem(value: 'add', child: Text('Add member')),
      const PopupMenuItem(value: 'rename', child: Text('Rename group')),
      PopupMenuItem(
        value: 'leave',
        child: Text('Leave group', style: TextStyle(color: colors.red)),
      ),
    ],
  );
}

class _DmHeaderTitle extends StatelessWidget {
  const _DmHeaderTitle({
    required this.title,
    required this.origin,
    required this.onTap,
    required this.onMenu,
  });

  final String title;
  final String? origin;
  final VoidCallback? onTap;
  final ValueChanged<Offset?>? onMenu;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (origin != null) ...[
          const SizedBox(width: 6),
          RemoteOriginBadge(domain: origin),
        ],
      ],
    );
    if (onTap == null && onMenu == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPressStart: onMenu == null
            ? null
            : (details) => onMenu!(details.globalPosition),
        onSecondaryTapUp: onMenu == null
            ? null
            : (details) => onMenu!(details.globalPosition),
        child: row,
      ),
    );
  }
}

class _DmUserGesture extends StatelessWidget {
  const _DmUserGesture({
    required this.user,
    required this.onTap,
    required this.onMenu,
    required this.child,
  });

  final AccordUser user;
  final VoidCallback onTap;
  final ValueChanged<Offset?> onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    child: GestureDetector(
      onTap: onTap,
      onLongPressStart: (details) => onMenu(details.globalPosition),
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: child,
    ),
  );
}

/// Prompts for a remote user's qualified handle (`<id>@<domain>`) to start a
/// cross-server DM. Pops the validated, trimmed handle on submit, or null on
/// cancel. Identity discovery is out of scope — the user supplies the handle
/// (e.g. shared out-of-band or copied from a remote profile).
class _RemoteDmDialog extends StatefulWidget {
  const _RemoteDmDialog();

  @override
  State<_RemoteDmDialog> createState() => _RemoteDmDialogState();
}

class _RemoteDmDialogState extends State<_RemoteDmDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A handle is valid when it is a qualified remote id: a non-empty local part
  /// and a home domain (`<id>@<domain>`). Local (bare) ids are rejected — this
  /// flow is specifically for users on another server.
  void _submit() {
    final value = _controller.text.trim();
    if (!isValidRemoteHandle(value)) {
      setState(
        () => _error = 'Enter a qualified handle, e.g. 123@server.example',
      );
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Message a remote user'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the user\'s qualified handle on their home server.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              isDense: true,
              hintText: '123@server.example',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Message')),
      ],
    );
  }
}
