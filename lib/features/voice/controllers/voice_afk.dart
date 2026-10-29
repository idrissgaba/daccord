part of 'voice.dart';

/// AFK detection for the local user: the idle monitor, the `idle` presence
/// other members see, and the move to the space's AFK channel. Split from
/// [VoiceController] for size; it only needs the session and the join lock.
mixin _VoiceAfk on _$VoiceController {
  VoiceSession? get _session;
  Future<void> _serialize(Future<void> Function() op);
  Future<void> _joinLocked(String channelId, String? spaceId);

  /// Idle detection for the local user. Created lazily so tests that override
  /// [build] (and so never join) don't install global input hooks.
  AfkMonitor? _afkMonitor;

  AfkMonitor _ensureAfkMonitor() {
    final existing = _afkMonitor;
    if (existing != null) return existing;
    final monitor = AfkMonitor()
      ..onAfkChanged = _onAfkChanged
      ..micActive = _micActive;
    return _afkMonitor = monitor;
  }

  /// The presence status we had before AFK flipped us to `idle`, so returning
  /// restores exactly what the user chose. Null when we didn't touch it.
  String? _presenceBeforeAfk;

  /// The connection key we published the `idle` status on, so it can be undone
  /// even after the voice session (and its `serverKey`) has gone away.
  String? _afkPresenceKey;

  // ── AFK ──
  //
  // Detection is client-side: `AccordVoiceState` has no `afk` field and
  // `updateVoiceState` accepts only the self_* flags, so AFK is published to
  // other members by flipping our presence to `idle`.

  /// Re-points the idle monitor at the current connection + timeout setting.
  void _syncAfk() {
    final minutes = ref.read(settingsControllerProvider).voiceAfkTimeoutMinutes;
    _ensureAfkMonitor().update(
      connected: state.isConnected,
      timeout: effectiveAfkTimeout(minutes),
    );
  }

  /// Whether the mic is picking us up right now — talking counts as activity
  /// even with no keyboard/mouse input. Muted means no input by definition.
  bool _micActive() {
    final session = _session;
    if (session == null || state.selfMute) return false;
    if (session.localIsSpeaking) return true;
    final threshold = ref.read(settingsControllerProvider).speakingThreshold;
    return session.localAudioLevel >= threshold;
  }

  void _onAfkChanged(bool afk) {
    if (state.isAfk == afk) return;
    state = state.copyWith(isAfk: afk);
    _publishAfkPresence(afk);
    if (afk) unawaited(_moveToAfkChannel());
  }

  /// Mirrors AFK onto our presence so *other* members can see it. Only ever
  /// touches a plain `online` status: a user who deliberately picked DND or
  /// Invisible keeps it, and we restore whatever they had on return.
  void _publishAfkPresence(bool afk) {
    // On the way back, use the connection we *published on* rather than the
    // current one: leaving voice clears `serverKey` before the AFK flag is
    // cleared, and a stranded `idle` status would never be restored.
    final key = afk ? state.serverKey : _afkPresenceKey;
    if (key == null) return;
    final client = ref.read(accordAuthProvider.notifier).clientForKey(key);
    final userId = ref
        .read(connectionsControllerProvider)
        .connectionFor(key)
        ?.session
        .userId;
    if (client == null || userId == null) return;
    final presences = ref.read(presenceControllerProvider(key));
    final current = accordPresenceStatus(presences, userId);

    if (afk) {
      if (current != 'online') return;
      _presenceBeforeAfk = current;
      _afkPresenceKey = key;
      _setPresence(client, key, userId, 'idle', presences);
    } else {
      final restore = _presenceBeforeAfk;
      _presenceBeforeAfk = null;
      _afkPresenceKey = null;
      // Don't stomp a status the user changed by hand while away.
      if (restore == null || current != 'idle') return;
      _setPresence(client, key, userId, restore, presences);
    }
  }

  void _setPresence(
    AccordClient client,
    String serverKey,
    String userId,
    String status,
    PresenceMap presences,
  ) {
    final custom = accordCustomStatus(presences, userId);
    client.gateway.updatePresence(
      status,
      activity: custom == null ? const {} : {'name': custom, 'type': 'custom'},
    );
    ref
        .read(presenceControllerProvider(serverKey).notifier)
        .upsert(
          AccordPresence(
            userId: userId,
            status: status,
            activities: custom == null
                ? []
                : [AccordActivity(name: custom, type: 'custom')],
          ),
        );
  }

  /// Moves us into the space's designated AFK channel, when it has one. Accord
  /// has no server-side move, so this is a plain re-join of the local user.
  Future<void> _moveToAfkChannel() async {
    if (!ref.read(settingsControllerProvider).voiceAfkAutoMove) return;
    final spaceId = state.spaceId;
    final serverKey = state.serverKey;
    if (spaceId == null || serverKey == null) return;
    // `_joinLocked` pins to whichever connection is *active*, so only auto-move
    // when the call is on that connection — otherwise we'd rejoin on the wrong
    // server.
    final connections = ref.read(connectionsControllerProvider);
    if (connections.activeKey != serverKey) return;
    final space = connections
        .connectionFor(serverKey)
        ?.spaces
        .firstWhereOrNull((s) => s.id == spaceId);
    final afkChannelId = space?.afkChannelId;
    if (afkChannelId == null ||
        afkChannelId.isEmpty ||
        afkChannelId == state.channelId) {
      return;
    }

    // Deliberately the private join: the public one marks activity and
    // re-syncs, which would immediately un-AFK us again.
    await _serialize(() => _joinLocked(afkChannelId, spaceId));
    if (state.isConnected && (_afkMonitor?.isAfk ?? false)) {
      state = state.copyWith(isAfk: true);
    }
  }
}
