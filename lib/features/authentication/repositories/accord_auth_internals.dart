part of 'accord_auth.dart';

/// The login machinery behind [AccordAuth]: REST clients, the login /
/// register / MFA attempts, session persistence, the connection table and
/// account switching. Split from the repository for size.
mixin _AuthInternals on _$AccordAuth {
  AccordSessionStore get _store;
  Map<String, _Conn> get _connections;
  String? keyForBaseUrl(String baseUrl);
  Future<void> logout();
  Future<void> _handleUnauthorized(String key);

  // ── internals ─────────────────────────────────────────────────────────────

  AccordClient _restClientFor(
    AccordServer server, {
    String token = '',
    String tokenType = 'Bearer',
  }) => AccordClient(
    token: token,
    tokenType: tokenType,
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
  );

  // The shared REST cores behind both the primary-login and add-a-server
  // flows. Each opens a throwaway unauthenticated client, maps
  // failures/exceptions to an [_AuthAttempt], and leaves state publication to
  // the caller (primary login publishes global [AccordAuthState]s;
  // add-a-server returns [AddServerOutcome]s so the home screen isn't bounced
  // to login).

  Future<_AuthAttempt> _attemptLogin(
    AccordServer server, {
    required String username,
    required String password,
  }) async {
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.login({
        'username': username,
        'password': password,
      });
      if (!result.ok) {
        return _AuthAttempt.error(result.error?.message ?? 'Login failed');
      }
      final data = result.data;
      if (data is Map && data['mfa_required'] == true) {
        return _AuthAttempt.mfa(data['ticket']?.toString() ?? '');
      }
      return _AuthAttempt.success(data);
    } catch (e) {
      return _AuthAttempt.error(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  Future<_AuthAttempt> _attemptRegister(
    AccordServer server, {
    required String username,
    required String password,
    String? displayName,
    String? inviteCode,
  }) async {
    final authClient = _restClientFor(server);
    try {
      final dn = displayName?.trim();
      final result = await authClient.auth.register(
        registrationBody(
          username: username,
          password: password,
          displayName: dn,
          inviteCode: inviteCode,
        ),
      );
      if (!result.ok) {
        return _AuthAttempt.error(
          result.error?.message ?? 'Registration failed',
        );
      }
      return _AuthAttempt.success(result.data);
    } catch (e) {
      return _AuthAttempt.error(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  Future<_AuthAttempt> _attemptMfa(
    AccordServer server, {
    required String ticket,
    required String code,
  }) async {
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.loginMfa({
        'ticket': ticket,
        'code': code,
      });
      if (!result.ok) {
        return _AuthAttempt.error(
          result.error?.message ?? 'Invalid two-factor code',
        );
      }
      return _AuthAttempt.success(result.data);
    } catch (e) {
      return _AuthAttempt.error(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  /// Builds the client-local session record for [user] authenticated against
  /// [server] with [token] — the one place the user→session field mapping
  /// lives.
  AccordSession _sessionFrom(
    AccordServer server,
    String token,
    AccordUser user, {
    String tokenType = 'Bearer',
  }) => AccordSession(
    server: server,
    token: token,
    tokenType: tokenType,
    userId: user.id,
    username: user.displayName ?? user.username,
    avatar: user.avatar,
    isAdmin: user.isAdmin,
  );

  /// Parses an `{ user, token }` auth payload into a session, or an error
  /// message when malformed. Shared by the login and add-a-server completions.
  ({AccordSession? session, String? error}) _sessionFromAuthData(
    AccordServer server,
    Object? data,
  ) {
    if (data is! Map) return (session: null, error: 'Malformed auth response');
    final token = data['token']?.toString();
    final user = data['user'];
    if (token == null || user is! AccordUser) {
      return (session: null, error: 'Auth response missing token or user');
    }
    return (session: _sessionFrom(server, token, user), error: null);
  }

  /// Verifies [token] against [server] and mints a session, or null if the
  /// token is rejected.
  Future<AccordSession?> _sessionFromToken(
    AccordServer server,
    String token,
    String tokenType,
  ) async {
    final probe = _restClientFor(server, token: token, tokenType: tokenType);
    try {
      final me = await probe.users.getMe();
      if (!me.ok || me.data is! AccordUser) return null;
      return _sessionFrom(
        server,
        token,
        me.data as AccordUser,
        tokenType: tokenType,
      );
    } finally {
      await probe.dispose();
    }
  }

  /// Parses an `{ user, token }` auth response and connects.
  Future<AccordAuthState> _completeLogin(
    AccordServer server,
    Object? data,
  ) async {
    final parsed = _sessionFromAuthData(server, data);
    if (parsed.error != null) return _fail(parsed.error!);
    final session = parsed.session!;
    if (data is Map && data['force_password_reset'] == true) {
      return _resetRequired(session);
    }
    try {
      await _store.persist(session);
    } catch (e) {
      return _fail('Secure credential storage failed: $e');
    }
    return await _addConnection(session, makeActive: true);
  }

  AccordAuthState _resetRequired(AccordSession pending, {String? error}) {
    final next = AccordAuthPasswordResetRequired(pending, error: error);
    state = next;
    return next;
  }

  String _accountKey(AccordSession session) => session.key;

  /// All saved accounts, for the switcher UI.
  Future<List<AccordSession>> listAccounts() => _store.listAccounts();

  /// Switches the active session to a previously saved [session]. If it is
  /// already connected this just flips active; otherwise it connects it.
  Future<AccordAuthState> switchTo(AccordSession session) async {
    final key = _accountKey(session);
    if (_connections.containsKey(key)) {
      await _store.persistActive(session);
      return _makeActive(key);
    }
    state = const AccordAuthInProgress();
    try {
      await _store.persist(session);
      return await _addConnection(session, makeActive: true);
    } catch (e) {
      return _fail(e.toString());
    }
  }

  /// Removes [session] from the saved account list and disconnects it if live.
  /// If it was the active connection, switches to another connected server or
  /// signs out when none remain.
  Future<void> removeAccount(AccordSession session) async {
    final key = _accountKey(session);
    final wasActive = ref.read(connectionsControllerProvider).activeKey == key;
    await _store.removeAccount(key);

    final conn = _connections.remove(key);
    if (conn != null) {
      ref.read(accordConnectionCoordinatorProvider).detach(key);
      await conn.client.dispose();
      ref.read(connectionsControllerProvider.notifier).remove(key);
    }
    ref.invalidate(readStateControllerProvider(key));
    ref.invalidate(mutedChannelsControllerProvider(key));
    ref.invalidate(presenceControllerProvider(key));
    ref.read(openTabsControllerProvider.notifier).removeForServer(key);
    unawaited(SpaceCache.remove(key));
    unawaited(PendingUploadStore.remove(key));
    ref.invalidate(pendingUploadsControllerProvider(key));

    if (wasActive) {
      final next = _connections.keys.isNotEmpty
          ? _connections.keys.first
          : null;
      if (next != null) {
        await _store.persistActive(_connections[next]!.session);
        _makeActive(next);
      } else {
        await logout();
      }
      return;
    }

    // Clear a stale active pointer left behind by a logged-out removal.
    final rawActive = await _store.readActiveRaw();
    if (rawActive is Map) {
      try {
        final stored = AccordSession.fromJson(
          Map<String, dynamic>.from(rawActive),
        );
        if (_accountKey(stored) == key) {
          await _store.deleteActive();
        }
      } catch (_) {
        // Ignore an unreadable active pointer.
      }
    }
  }

  /// Tears down the live connection [key] (gateway + event subscriptions) and
  /// drops it from the rail registry. Used to replace an account when a new one
  /// signs in to the same server. Does not touch the saved-account list — the
  /// caller's [_persist] dedupes that.
  Future<void> _evictConnection(String key) async {
    final conn = _connections.remove(key);
    if (conn != null) {
      ref.read(accordConnectionCoordinatorProvider).detach(key);
      await conn.client.dispose();
    }
    ref.read(connectionsControllerProvider.notifier).remove(key);
    ref.invalidate(readStateControllerProvider(key));
    ref.invalidate(mutedChannelsControllerProvider(key));
    ref.invalidate(presenceControllerProvider(key));
    ref.read(openTabsControllerProvider.notifier).removeForServer(key);
    unawaited(SpaceCache.remove(key));
    unawaited(PendingUploadStore.remove(key));
    ref.invalidate(pendingUploadsControllerProvider(key));
  }

  /// Connects [session] as a live server (or, if already connected, optionally
  /// makes it active). Background connections (makeActive: false) keep the
  /// current `state` untouched.
  Future<AccordAuthState> _addConnection(
    AccordSession session, {
    required bool makeActive,
    bool replaceExisting = false,
  }) async {
    final key = _accountKey(session);
    if (_connections.containsKey(key)) {
      return makeActive ? _makeActive(key) : state;
    }

    // One account per server: a server is owned by a single account at a time.
    // If a *different* account is already live on this server, an explicit
    // (active) login replaces it; a background restore must not stack a second
    // connection onto the same server (which would duplicate its rail group).
    final existingOnServer = keyForBaseUrl(session.server.baseUrl);
    if (existingOnServer != null && existingOnServer != key) {
      if (!makeActive && !replaceExisting) return state;
      await _evictConnection(existingOnServer);
      // Another lookup may have installed this same session during disposal.
      if (_connections.containsKey(key)) {
        return makeActive ? _makeActive(key) : state;
      }
    }

    ref
        .read(connectionsControllerProvider.notifier)
        .register(session, status: ConnectionStatus.connecting);

    // First point at which notifications mean anything: there is an account
    // whose mentions we could post. Asking at startup instead put the OS
    // permission alert over the terms gate. Fire-and-forget — the prompt must
    // not delay the connection, and it no-ops after the first call.
    unawaited(requestNotificationPermissions());

    // Seed the rail from the last-known cache so this server's spaces show
    // immediately (dimmed, while connecting/unreachable) instead of waiting on
    // READY — which never arrives if the server is offline. The gateway READY
    // overwrites this with the authoritative list once connected.
    final cachedSpaces = SpaceCache.load(key);
    if (cachedSpaces.isNotEmpty) {
      ref
          .read(connectionsControllerProvider.notifier)
          .setSpaces(key, cachedSpaces);
    }

    final client = AccordClient(
      encryptionStore: session.isGuest ? null : PlatformEncryptionKeyStore(),
      encryptionUserId: session.isGuest ? null : session.userId,
      token: session.token,
      tokenType: session.tokenType,
      baseUrl: session.server.baseUrl,
      gatewayUrl: session.server.gatewayUrl,
      cdnUrl: session.server.cdnUrl,
      onUnauthorized: () => _handleUnauthorized(key),
      intents: session.isGuest
          ? GatewayIntents.guest()
          : [
              GatewayIntents.spaces,
              GatewayIntents.messages,
              GatewayIntents.messageContent,
              GatewayIntents.messageReactions,
              GatewayIntents.messageTyping,
              GatewayIntents.members,
              GatewayIntents.presences,
              GatewayIntents.voiceStates,
              GatewayIntents.experiences,
              GatewayIntents.scheduledEvents,
            ],
    );
    _connections[key] = _Conn(client: client, session: session);
    ref
        .read(accordConnectionCoordinatorProvider)
        .attach(
          client: client,
          session: session,
          isActive: () =>
              ref.read(connectionsControllerProvider).activeKey == key,
        );
    // Provision while online so other participants can encrypt offline delivery.
    unawaited(client.encryption?.initialize().catchError((Object _) {}));
    client.login();

    if (makeActive) return _makeActive(key);
    return state;
  }

  /// Promotes the connection [key] to active: snapshots the outgoing server's
  /// live spaces into its rail cache, seeds the shared rail from [key]'s cache,
  /// publishes the logged-in state. Existing panes/controllers then
  /// transparently read the new active client.
  AccordAuthState _makeActive(String key) {
    final conn = _connections[key];
    if (conn == null) return state;

    final connections = ref.read(connectionsControllerProvider.notifier);

    // Capture the outgoing active server's live spaces (incl. roles, which only
    // the shared controller has) so they persist while it's backgrounded.
    final prevKey = ref.read(connectionsControllerProvider).activeKey;
    if (prevKey != null && prevKey != key) {
      final liveSpaces = ref.read(spacesControllerProvider);
      if (liveSpaces != null) connections.setSpaces(prevKey, liveSpaces);
    }

    connections.setActive(key);
    ref.read(settingsControllerProvider.notifier).claimLegacyEntityKeys(key);

    // Seed the shared rail/space controllers from this connection's cache so
    // panes have data immediately; the gateway READY refreshes it.
    final cached = connections.spacesFor(key);
    ref.read(spacesControllerProvider.notifier).setSpaces(cached);

    final next = AccordAuthLoggedIn(client: conn.client, session: conn.session);
    state = next;
    if (!conn.session.isGuest) unawaited(_store.persistActive(conn.session));
    return next;
  }

  AccordAuthState _fail(String message) {
    final next = AccordAuthFailed(message);
    state = next;
    return next;
  }
}
