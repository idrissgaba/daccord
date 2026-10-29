import 'dart:async';
import 'package:bonfire/features/authentication/repositories/encryption_key_store.dart';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_session_store.dart';
import 'package:bonfire/features/authentication/utils/credential_validation.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/controllers/muted_channels.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/voice/controllers/missed_calls.dart';
import 'package:bonfire/features/events/services/accord_connection_coordinator.dart';
import 'package:bonfire/features/notifications/services/notification.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/messaging/controllers/pending_uploads.dart';
import 'package:bonfire/features/messaging/utils/pending_upload_store.dart';
import 'package:bonfire/features/server/utils/space_cache.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'accord_auth.g.dart';
part 'accord_auth_add_server.dart';
part 'accord_auth_internals.dart';

/// One live server connection and the [AccordSession] that opened it. Gateway
/// subscription ownership lives in [AccordConnectionCoordinator].
class _Conn {
  final AccordClient client;
  final AccordSession session;

  _Conn({required this.client, required this.session});
}

/// Neutral result of an auth REST call, before any state publication: exactly
/// one of [data] (success payload), [mfaTicket], or [error] is meaningful.
class _AuthAttempt {
  final Object? data;
  final String? mfaTicket;
  final String? error;

  const _AuthAttempt._({this.data, this.mfaTicket, this.error});

  factory _AuthAttempt.success(Object? data) => _AuthAttempt._(data: data);
  factory _AuthAttempt.mfa(String ticket) => _AuthAttempt._(mfaTicket: ticket);
  factory _AuthAttempt.error(String message) => _AuthAttempt._(error: message);
}

/// Authentication + connection lifecycle against Accord servers. The Accord
/// replacement for the Discord-specific `Auth` provider.
///
/// In the multi-server model this holds N live [AccordClient]s at once (one per
/// connected server, keyed by `userId@baseUrl`) and tracks which one is
/// *active*. `state` (an [AccordAuthLoggedIn]) and [client] always refer to the
/// active connection, so every existing pane/controller keeps reading the active
/// server unchanged. Background connections stay logged in (gateways open,
/// spaces cached in `ConnectionsController`) so the rail can show every server's
/// spaces at once; selecting a space on another server flips the active
/// connection without re-authenticating.
@Riverpod(keepAlive: true)
class AccordAuth extends _$AccordAuth with _AuthInternals, _AddServer {
  AccordAuth({AccordSessionStore? sessionStore})
    : _store = sessionStore ?? AccordSessionStore();

  @override
  final AccordSessionStore _store;
  @override
  final Map<String, _Conn> _connections = {};
  Future<AccordAuthState>? _restoration;

  /// Connection keys currently being torn down after a 401, so the burst of
  /// simultaneous unauthorized responses (spaces, members, emojis, …) triggers
  /// exactly one sign-out per connection.
  final Set<String> _signingOut = {};

  /// The active connection's client, or null when signed out. Repositories
  /// should obtain this via the logged-in [AccordAuthLoggedIn] state rather than
  /// reaching in here.
  AccordClient? get client {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    return activeKey == null ? null : _connections[activeKey]?.client;
  }

  /// The active connection's client for [key], if connected.
  AccordClient? clientForKey(String key) => _connections[key]?.client;

  /// The connection key (`userId@baseUrl`) currently connected to [baseUrl], if
  /// any — used by the deep-link/add-server flow to detect "already connected".
  String? keyForBaseUrl(String baseUrl) {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    final active = _connections[activeKey];
    if (active != null &&
        AccordServer.sameEndpoint(active.session.server.baseUrl, baseUrl)) {
      return activeKey;
    }
    for (final conn in _connections.values) {
      if (AccordServer.sameEndpoint(conn.session.server.baseUrl, baseUrl)) {
        return conn.session.key;
      }
    }
    return null;
  }

  /// Finds a saved account even before startup has created its live client.
  /// Prefer the active account, including the persisted active pointer while
  /// restoration is still reading credentials from the platform vault.
  Future<AccordSession?> accountForBaseUrl(String baseUrl) async {
    AccordSession? activeLiveSession() {
      final key = ref.read(connectionsControllerProvider).activeKey;
      final active = _connections[key]?.session;
      return active != null &&
              AccordServer.sameEndpoint(active.server.baseUrl, baseUrl)
          ? active
          : null;
    }

    final liveActive = activeLiveSession();
    if (liveActive != null) return liveActive;
    final accounts = await listAccounts();
    final active = await _store.readRestorableActive();
    // Restoration may have published the active account during the vault read.
    final currentActive = activeLiveSession();
    if (currentActive != null) return currentActive;
    if (active != null &&
        AccordServer.sameEndpoint(active.server.baseUrl, baseUrl)) {
      return active;
    }
    final liveKey = keyForBaseUrl(baseUrl);
    if (liveKey != null) return _connections[liveKey]?.session;
    for (final account in accounts) {
      if (AccordServer.sameEndpoint(account.server.baseUrl, baseUrl)) {
        return account;
      }
    }
    return null;
  }

  /// Ensures a saved account has a REST/gateway client without switching the
  /// visible account or publishing a login-in-progress state. Null means no
  /// saved account exists; connection errors must be shown instead of asking
  /// for a second set of credentials.
  Future<String?> ensureConnectionForBaseUrl(String baseUrl) async {
    final liveKey = keyForBaseUrl(baseUrl);
    if (liveKey != null &&
        liveKey == ref.read(connectionsControllerProvider).activeKey) {
      return liveKey;
    }
    final session = await accountForBaseUrl(baseUrl);
    if (session == null) return null;
    if (clientForKey(session.key) != null) return session.key;
    await _addConnection(session, makeActive: false, replaceExisting: true);
    if (clientForKey(session.key) == null) {
      throw StateError('Could not reconnect the saved account');
    }
    return session.key;
  }

  /// Joins on the selected account and populates its rail cache before callers
  /// activate it. A 409 means existing membership; fetch the space if needed.
  Future<({String? spaceId, String? error})> joinOnConnection(
    String key, {
    String? spaceId,
    String? invite,
  }) async {
    if (spaceId == null && invite == null) return (spaceId: null, error: null);
    if (invite == null) {
      final cached = ref.read(connectionsControllerProvider).connectionFor(key);
      for (final space in cached?.spaces ?? const <AccordSpace>[]) {
        if (space.id == spaceId ||
            space.slug == spaceId ||
            space.name == spaceId) {
          // Existing private membership can be opened without attempting the
          // public-space join endpoint, which correctly rejects private spaces.
          return (spaceId: space.id, error: null);
        }
      }
    }
    final target = clientForKey(key);
    if (target == null) return (spaceId: null, error: 'Connection unavailable');
    final result = invite != null
        ? await target.invites.accept(invite)
        : await target.spaces.join(spaceId!);
    if (!result.ok && result.statusCode != 409) {
      return (spaceId: null, error: result.error?.message ?? 'Failed to join');
    }
    var space = result.data;
    var joinedSpaceId = spaceId;
    // Both join endpoints currently expose raw JSON through accordkit.
    if (space is Map) {
      final nested = space['space'];
      if (nested is Map) {
        space = AccordSpace.fromJson(Map<String, dynamic>.from(nested));
      } else if (space['id'] != null) {
        space = AccordSpace.fromJson(Map<String, dynamic>.from(space));
      } else {
        joinedSpaceId = space['space_id']?.toString() ?? joinedSpaceId;
      }
    }
    if (space is! AccordSpace && joinedSpaceId == null && invite != null) {
      final details = await target.invites.fetch(invite);
      final invitation = details.data;
      if (invitation is AccordInvite) joinedSpaceId = invitation.spaceId;
    }
    if (space is! AccordSpace && joinedSpaceId != null) {
      final fetched = await target.spaces.fetch(joinedSpaceId);
      space = fetched.data;
    }
    if (space is! AccordSpace || space.id.isEmpty) {
      return (spaceId: null, error: 'Server returned no joined space');
    }
    ref.read(connectionsControllerProvider.notifier).upsertSpace(key, space);
    if (ref.read(connectionsControllerProvider).activeKey == key) {
      ref.read(spacesControllerProvider.notifier).upsertSpace(space);
    }
    return (spaceId: space.id, error: null);
  }

  @override
  AccordAuthState build() {
    final connectionCoordinator = ref.read(accordConnectionCoordinatorProvider);
    ref.onDispose(() {
      connectionCoordinator.detachAll();
      for (final conn in _connections.values) {
        conn.client.dispose();
      }
      _connections.clear();
    });
    return const AccordAuthLoggedOut();
  }

  /// Logs in to [server] with [username]/[password]. Returns an
  /// [AccordAuthMfaRequired] state when the server demands a second factor;
  /// follow up with [submitMfa].
  Future<AccordAuthState> loginWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
  }) async {
    state = const AccordAuthInProgress();
    final attempt = await _attemptLogin(
      server,
      username: username,
      password: password,
    );
    if (attempt.error != null) return _fail(attempt.error!);
    if (attempt.mfaTicket != null) {
      final next = AccordAuthMfaRequired(
        ticket: attempt.mfaTicket!,
        server: server,
      );
      state = next;
      return next;
    }
    return await _completeLogin(server, attempt.data);
  }

  /// Registers a new account on [server] and logs straight in. [displayName]
  /// defaults to [username] when blank. [inviteCode] is sent along so a server
  /// whose registration policy is `invite_only` can admit the account.
  Future<AccordAuthState> registerWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
    String? displayName,
    String? inviteCode,
  }) async {
    // The server enforces the username rule authoritatively as well.
    final usernameError = validateRegistrationUsername(username);
    if (usernameError != null) return _fail(usernameError);
    state = const AccordAuthInProgress();
    final attempt = await _attemptRegister(
      server,
      username: username,
      password: password,
      displayName: displayName,
      inviteCode: inviteCode,
    );
    if (attempt.error != null) return _fail(attempt.error!);
    return await _completeLogin(server, attempt.data);
  }

  /// Connects to [server] as an anonymous guest (read-only). The guest token is
  /// transient, so the session is **not** persisted or added to the saved
  /// account list. The sign-in surface keeps this mode hidden until all write
  /// affordances can consume the explicit guest restriction.
  Future<AccordAuthState> loginAsGuest(AccordServer server) async {
    state = const AccordAuthInProgress();
    final authClient = _restClientFor(server);
    try {
      final result = await authClient.auth.guest();
      if (!result.ok) {
        return _fail(result.error?.message ?? 'Guest access not available');
      }
      final data = result.data;
      if (data is! Map) {
        return _fail('Unexpected guest response');
      }
      final token = data['token']?.toString();
      if (token == null || token.isEmpty) {
        return _fail('No guest token received');
      }

      final probe = _restClientFor(server, token: token);
      try {
        final me = await probe.users.getMe();
        if (!me.ok || me.data is! AccordUser) {
          return _fail(me.error?.message ?? 'Guest connection failed');
        }
        final user = me.data as AccordUser;
        final base = _sessionFrom(server, token, user);
        final session = AccordSession(
          server: base.server,
          token: base.token,
          tokenType: base.tokenType,
          userId: base.userId,
          username: base.username,
          avatar: base.avatar,
          isAdmin: false,
          isGuest: true,
          expiresAt: guestSessionExpiry(data, token),
        );
        if (session.isExpired) return _fail('Guest token already expired');
        // Intentionally not persisted: guest sessions are transient.
        return await _addConnection(session, makeActive: true);
      } finally {
        await probe.dispose();
      }
    } catch (e) {
      return _fail(e.toString());
    } finally {
      await authClient.dispose();
    }
  }

  /// Fetches a server's public settings (e.g. Terms-of-Service config) before
  /// login. Exactly one of [settings] (the map, with a `{ data: {...} }`
  /// envelope unwrapped) and [error] is non-null, so callers can tell "the
  /// server said nothing is configured" from "we never got an answer".
  ///
  /// [statusCode] carries the HTTP status the failure came with (`0` when the
  /// request never produced a response at all), because the *reason* matters:
  /// accordserver serves `GET /settings` to authenticated users only, so a
  /// signed-out read reliably 401s and callers treat that structural refusal
  /// differently from an unexpected failure (#289).
  Future<({Map<String, dynamic>? settings, String? error, int statusCode})>
  fetchServerSettings(AccordServer server) async {
    final client = _restClientFor(server);
    try {
      final result = await client.rest.makeRequest('GET', '/settings');
      if (!result.ok || result.data is! Map) {
        final message =
            result.error?.message ??
            (result.ok
                ? 'Unexpected settings response'
                : 'HTTP ${result.statusCode}');
        debugPrint(
          'Failed to read ${server.baseUrl} settings '
          '(${result.statusCode}): $message',
        );
        return (settings: null, error: message, statusCode: result.statusCode);
      }
      final map = Map<String, dynamic>.from(result.data as Map);
      final inner = map['data'];
      return (
        settings: inner is Map ? Map<String, dynamic>.from(inner) : map,
        error: null,
        statusCode: result.statusCode,
      );
    } catch (e) {
      debugPrint('Failed to read ${server.baseUrl} settings: $e');
      return (settings: null, error: e.toString(), statusCode: 0);
    } finally {
      await client.dispose();
    }
  }

  /// Completes an MFA challenge from [loginWithCredentials] with a TOTP or
  /// backup [code].
  Future<AccordAuthState> submitMfa(String code) async {
    final current = state;
    if (current is! AccordAuthMfaRequired) {
      return _fail('No MFA challenge in progress');
    }
    final server = current.server;
    state = const AccordAuthInProgress();
    final attempt = await _attemptMfa(
      server,
      ticket: current.ticket,
      code: code,
    );
    if (attempt.error != null) return _fail(attempt.error!);
    return await _completeLogin(server, attempt.data);
  }

  /// Resolves an [AccordAuthPasswordResetRequired] challenge: changes the
  /// password using the temporary token, then connects the now-usable session.
  Future<AccordAuthState> submitPasswordChange({
    required String oldPassword,
    required String newPassword,
  }) async {
    final current = state;
    if (current is! AccordAuthPasswordResetRequired) {
      return _fail('No password change in progress');
    }
    final pending = current.pending;
    state = const AccordAuthInProgress();

    final authed = _restClientFor(
      pending.server,
      token: pending.token,
      tokenType: pending.tokenType,
    );
    try {
      final result = await authed.auth.changePassword({
        'old_password': oldPassword,
        'new_password': newPassword,
      });
      if (!result.ok) {
        return _resetRequired(
          pending,
          error: result.error?.message ?? 'Password change failed',
        );
      }
      await _store.persist(pending);
      return await _addConnection(pending, makeActive: true);
    } catch (e) {
      return _resetRequired(pending, error: e.toString());
    } finally {
      await authed.dispose();
    }
  }

  /// Restores the persisted active session (and any other saved accounts) and
  /// reconnects their gateways. The active account is connected first and its
  /// logged-in state returned for navigation; the rest connect in the
  /// background so the rail can show every server's spaces. Returns
  /// [AccordAuthLoggedOut] when nothing is stored.
  Future<AccordAuthState> restoreSession() => _restoration ??= _restoreSession()
      .whenComplete(() => _restoration = null);

  Future<AccordAuthState> _restoreSession() async {
    if (state is AccordAuthLoggedIn) return state;
    AccordSession? active;
    try {
      active = await _store.readRestorableActive();
    } catch (e) {
      debugPrint('Failed to restore Accord session: $e');
      // A locked/unavailable platform credential vault can be temporary. Keep
      // the opaque pointer (and any legacy plaintext awaiting migration) so a
      // later launch can recover instead of destroying the only credential.
      return _fail(e.toString());
    }
    if (active == null) return const AccordAuthLoggedOut();

    // A join can activate another saved account while the vault read awaits.
    final result = await _addConnection(
      active,
      makeActive: state is! AccordAuthLoggedIn,
    );

    // Reconnect every other saved account in the background.
    final activeKey = active.key;
    final accounts = await listAccounts();
    for (final session in accounts) {
      if (session.key == activeKey) continue;
      unawaited(_addConnection(session, makeActive: false));
    }

    // Prune tabs owned by accounts that no longer exist (e.g. logged out before
    // this restore), so the strip doesn't show stale/duplicate tabs.
    final knownServers = {activeKey, for (final s in accounts) s.key};
    ref.read(openTabsControllerProvider.notifier).retainServers(knownServers);
    return result;
  }

  /// Tears down every live connection and clears the active session pointer.
  Future<void> logout() async {
    ref.read(accordConnectionCoordinatorProvider).detachAll();
    for (final conn in _connections.values) {
      await conn.client.dispose();
    }
    _connections.clear();

    await _store.deleteActive();

    ref.read(connectionsControllerProvider.notifier).clear();
    ref.invalidate(accordUsersControllerProvider);
    ref.invalidate(mutedChannelsControllerProvider);
    ref.invalidate(readStateControllerProvider);
    ref.invalidate(presenceControllerProvider);
    // Missed calls are session-only and in-memory, so without this they would
    // survive a sign-out that doesn't restart the app.
    ref.read(missedCallsControllerProvider.notifier).clearAll();
    ref.read(openTabsControllerProvider.notifier).clear();
    unawaited(SpaceCache.clear());
    unawaited(PendingUploadStore.clear());
    ref.invalidate(pendingUploadsControllerProvider);
    ref.read(spacesControllerProvider.notifier).setSpaces(const []);
    state = const AccordAuthLoggedOut();
  }

  /// Reacts to a `401 Unauthorized` from connection [key]: its token is invalid
  /// or expired and accordkit exposes no refresh path, so the session can't be
  /// recovered silently. Sign the affected account out via [removeAccount],
  /// which switches to another live server if one exists or otherwise
  /// [logout]s to the login screen — matching "log me back in" rather than
  /// leaving cached spaces/channels rendered behind a dead token.
  ///
  /// Guarded by [_signingOut] so the burst of simultaneous 401s (spaces,
  /// members, emojis, …) tears the connection down exactly once; a no-op once
  /// the connection is already gone.
  Future<void> _handleUnauthorized(String key) async {
    if (_signingOut.contains(key)) return;
    final conn = _connections[key];
    if (conn == null) return;
    _signingOut.add(key);
    debugPrint(
      'Session $key is unauthorized (token invalid/expired); '
      'signing it out.',
    );
    try {
      await removeAccount(conn.session);
    } finally {
      _signingOut.remove(key);
    }
  }
}

/// Result of an add-a-server attempt while already logged in. Distinct from the
/// global [AccordAuthState] so the dialog can surface its own MFA/error flow
/// without disturbing the active connection.
class AddServerOutcome {
  final bool ok;
  final String? error;
  final String? mfaTicket;
  final AccordSession? passwordResetSession;

  const AddServerOutcome._({
    this.ok = false,
    this.error,
    this.mfaTicket,
    this.passwordResetSession,
  });

  factory AddServerOutcome.ok() => const AddServerOutcome._(ok: true);
  factory AddServerOutcome.error(String message) =>
      AddServerOutcome._(error: message);
  factory AddServerOutcome.mfa(String ticket) =>
      AddServerOutcome._(mfaTicket: ticket);
  factory AddServerOutcome.passwordReset(
    AccordSession pending, {
    String? error,
  }) => AddServerOutcome._(passwordResetSession: pending, error: error);

  bool get needsMfa => mfaTicket != null;
  bool get needsPasswordReset => passwordResetSession != null;
}

/// The `POST /auth/register` body. `invite_code` is only sent when there is
/// one: servers whose policy is `invite_only` require it, the others ignore
/// unknown fields.
@visibleForTesting
Map<String, dynamic> registrationBody({
  required String username,
  required String password,
  String? displayName,
  String? inviteCode,
}) {
  final invite = inviteCode?.trim();
  return {
    'username': username,
    'password': password,
    'display_name': (displayName == null || displayName.isEmpty)
        ? username
        : displayName,
    if (invite != null && invite.isNotEmpty) 'invite_code': invite,
  };
}
