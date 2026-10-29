part of 'accord_home.dart';

/// The home screen's app-wide keyboard shortcuts and the handlers behind the
/// MCP `navigate` tools. Split from [_AccordHomeScreenState] for size; both
/// only route into the screen's selection and open methods declared below.
mixin _HomeNavigation on ConsumerState<AccordHomeScreen> {
  bool get _memberListVisible;
  set _memberListVisible(bool value);
  void _selectSpace(String serverKey, String spaceId);
  Future<bool> _openChannel(String channelId, {required String spaceId});
  void _openSearchSelection(AccordSearchSelection selection);

  /// App-wide shortcuts (Ctrl+K, Alt+↑/↓, Ctrl+Shift+M, …). A hardware-level
  /// handler rather than a `Shortcuts` widget so they work whatever has
  /// focus, including nothing at all after a click on the channel list. Only
  /// while this screen is the current route: a dialog's own keys (the quick
  /// switcher's ↑/↓) must not reach here.
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    final mods = HardwareKeyboard.instance;
    final shortcut = matchHomeShortcut(
      pressed: event.logicalKey,
      control: mods.isControlPressed || mods.isMetaPressed,
      shift: mods.isShiftPressed,
      alt: mods.isAltPressed,
      physicalPressed: event.physicalKey.usbHidUsage,
      custom: ref.read(settingsControllerProvider).keybinds,
      disabledDefaults: ref
          .read(settingsControllerProvider)
          .disabledDefaultKeybinds,
    );
    if (shortcut == null) return false;
    unawaited(_runShortcut(shortcut));
    return true;
  }

  Future<void> _runShortcut(HomeShortcut shortcut) async {
    final shown = mcpHomeBridge.state;
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    switch (shortcut) {
      case HomeShortcut.quickSwitcher:
        final target = await showQuickSwitcher(context);
        if (target == null || !mounted || activeKey == null) return;
        _selectSpace(activeKey, target.spaceId);
        await _openChannel(target.channelId, spaceId: target.spaceId);
      case HomeShortcut.previousChannel:
      case HomeShortcut.nextChannel:
        final spaceId = shown.spaceId;
        if (spaceId == null || activeKey == null) return;
        final channels =
            ref.read(accordChannelsControllerProvider(activeKey, spaceId)) ??
            const <AccordChannel>[];
        final next = adjacentId(
          orderedNavigableChannelIds(channels),
          shown.channelId,
          forward: shortcut == HomeShortcut.nextChannel,
        );
        if (next != null) await _openChannel(next, spaceId: spaceId);
      case HomeShortcut.previousSpace:
      case HomeShortcut.nextSpace:
        final current = activeKey == null || shown.spaceId == null
            ? null
            : ServerEntityKey(activeKey, shown.spaceId!).encoded;
        final next = adjacentId(
          _railSpaceKeys(),
          current,
          forward: shortcut == HomeShortcut.nextSpace,
        );
        final target = next == null ? null : ServerEntityKey.tryDecode(next);
        if (target != null) _selectSpace(target.serverKey, target.entityId);
      // While in a call on Windows the voice controller watches these chords
      // system-wide and has already toggled.
      case HomeShortcut.toggleMute:
        final voice = ref.read(voiceControllerProvider.notifier);
        if (!voice.watchesVoiceShortcutsGlobally) voice.toggleMute();
      case HomeShortcut.toggleDeafen:
        final voice = ref.read(voiceControllerProvider.notifier);
        if (!voice.watchesVoiceShortcutsGlobally) voice.toggleDeafen();
      case HomeShortcut.toggleMembers:
        setState(() => _memberListVisible = !_memberListVisible);
      case HomeShortcut.openSettings:
        context.push('/settings');
      case HomeShortcut.showShortcuts:
        await showKeyboardShortcutsDialog(context);
    }
  }

  /// The rail's spaces (every connection, minus hidden ones) as encoded
  /// entity keys, in the order the rail draws them.
  List<String> _railSpaceKeys() {
    final connections = ref.read(connectionsControllerProvider);
    final settings = ref.read(settingsControllerProvider);
    final live = ref.read(spacesControllerProvider);
    final keys = <String>[];
    for (final conn in connections.connections) {
      final spaces = conn.key == connections.activeKey
          ? (live ?? conn.spaces)
          : conn.spaces;
      for (final space in spaces) {
        final key = ServerEntityKey(conn.key, space.id).encoded;
        if (!settings.hiddenSpaces.contains(key)) keys.add(key);
      }
    }
    return orderBySavedOrder(keys, settings.spaceOrder);
  }

  /// Navigation handlers the local MCP server's `navigate` tools delegate to.
  /// Each receives the argument map already resolved by the tools layer and
  /// returns an MCP result map.
  Map<String, McpNavHandler> _mcpNavHandlers() => {
    'select_space': (args) async {
      _selectSpace(args['server_key'] as String, args['space_id'] as String);
      return {'ok': true};
    },
    'select_channel': (args) async {
      await _openChannel(
        args['channel_id'] as String,
        spaceId: args['space_id'] as String,
      );
      return {'ok': true};
    },
    'open_dm': (args) async {
      if (!mounted) return _mcpUnmounted;
      showAccordDirectMessages(context);
      return {'ok': true};
    },
    'open_settings': (args) async {
      if (!mounted) return _mcpUnmounted;
      context.push('/settings');
      return {'ok': true};
    },
    'open_discovery': (args) async {
      if (!mounted) return _mcpUnmounted;
      showAccordDiscovery(context);
      return {'ok': true};
    },
    'open_thread': (args) async {
      if (!mounted) return _mcpUnmounted;
      final channelId = args['channel_id'] as String;
      final messageId = args['message_id'] as String;
      final root = ref
          .read(
            accordMessagesControllerProvider(
              ref.readActiveServerKey() ?? '',
              channelId,
            ),
          )
          ?.firstWhereOrNull((m) => m.id == messageId);
      if (root == null) return {'error': 'Message not loaded'};
      showAccordThread(context, channelId: channelId, root: root);
      return {'ok': true};
    },
    // Reveals the *current* call's channel; it never joins one (matching the
    // rest of the app after #202 — navigation is never a connect). It stays an
    // error when nothing is connected rather than silently joining something:
    // `select_channel` already opens any voice channel's lobby.
    'open_voice_view': (args) async {
      if (!mounted) return _mcpUnmounted;
      final voice = ref.read(voiceControllerProvider);
      if (!voice.isConnected) {
        return {'error': 'Not connected to a voice channel'};
      }
      await _openChannel(voice.channelId!, spaceId: voice.spaceId!);
      return {'ok': true};
    },
    'toggle_member_list': (args) async {
      if (!mounted) return _mcpUnmounted;
      setState(() => _memberListVisible = !_memberListVisible);
      return {'ok': true, 'visible': _memberListVisible};
    },
    'toggle_search': (args) async {
      if (!mounted) return _mcpUnmounted;
      final spaceId = mcpHomeBridge.state.spaceId;
      if (spaceId == null || spaceId.isEmpty) {
        return {'error': 'No space selected'};
      }
      final selection = await showAccordSearch(context, spaceId: spaceId);
      if (mounted && selection != null) _openSearchSelection(selection);
      return {'ok': true};
    },
  };

  static const Map<String, dynamic> _mcpUnmounted = {
    'error': 'Home screen not mounted',
  };
}
