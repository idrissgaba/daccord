part of 'accord_auth.dart';

/// Connecting an additional server while staying logged in. Split from
/// [AccordAuth] for size; it only needs the connection table and the login
/// internals.
mixin _AddServer on _$AccordAuth, _AuthInternals {
  // ── Add-a-server (multi-connection) ────────────────────────────────────────
  // These connect an *additional* server while staying logged in. Unlike the
  // primary login flow they must NOT publish a global [AccordAuthInProgress]
  // state (that would bounce the home screen to /login); they keep the current
  // active connection until the new one succeeds.

  /// Connects an additional [server] with an existing [token], persists it, and
  /// makes it active. Returns null on success or an error message on failure.
  Future<String?> addServerWithToken({
    required AccordServer server,
    required String token,
    String tokenType = 'Bearer',
  }) async {
    try {
      final session = await _sessionFromToken(server, token, tokenType);
      if (session == null) return 'Token rejected';
      await _store.persist(session);
      await _addConnection(session, makeActive: true);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Connects an additional [server] with [username]/[password], persists it,
  /// and makes it active. Reports MFA challenges via [AddServerOutcome.mfa].
  Future<AddServerOutcome> addServerWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
  }) async {
    final attempt = await _attemptLogin(
      server,
      username: username,
      password: password,
    );
    if (attempt.error != null) return AddServerOutcome.error(attempt.error!);
    if (attempt.mfaTicket != null) {
      return AddServerOutcome.mfa(attempt.mfaTicket!);
    }
    return await _completeAddServer(server, attempt.data);
  }

  /// Registers a new account on [server] and connects it as an additional
  /// server, persisting it and making it active. The add-a-server counterpart
  /// to [registerWithCredentials] (which is for the primary login flow): it
  /// returns an [AddServerOutcome] instead of publishing a global
  /// [AccordAuthInProgress] state, so the home screen isn't bounced to login.
  Future<AddServerOutcome> addServerWithRegister({
    required AccordServer server,
    required String username,
    required String password,
    String? displayName,
    String? inviteCode,
  }) async {
    final usernameError = validateRegistrationUsername(username);
    if (usernameError != null) return AddServerOutcome.error(usernameError);
    final attempt = await _attemptRegister(
      server,
      username: username,
      password: password,
      displayName: displayName,
      inviteCode: inviteCode,
    );
    if (attempt.error != null) return AddServerOutcome.error(attempt.error!);
    return await _completeAddServer(server, attempt.data);
  }

  /// Completes an MFA challenge raised by [addServerWithCredentials].
  Future<AddServerOutcome> addServerSubmitMfa(
    AccordServer server,
    String ticket,
    String code,
  ) async {
    final attempt = await _attemptMfa(server, ticket: ticket, code: code);
    if (attempt.error != null) return AddServerOutcome.error(attempt.error!);
    return await _completeAddServer(server, attempt.data);
  }

  /// Resolves a forced-password-reset challenge without disturbing the
  /// currently active connection. The temporary [pending] session is persisted
  /// and connected only after the password change succeeds.
  Future<AddServerOutcome> addServerSubmitPasswordChange({
    required AccordSession pending,
    required String oldPassword,
    required String newPassword,
  }) async {
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
        return AddServerOutcome.passwordReset(
          pending,
          error: result.error?.message ?? 'Password change failed',
        );
      }
      await _store.persist(pending);
      await _addConnection(pending, makeActive: true);
      return AddServerOutcome.ok();
    } catch (e) {
      return AddServerOutcome.passwordReset(pending, error: e.toString());
    } finally {
      await authed.dispose();
    }
  }

  /// The add-a-server counterpart to [_completeLogin]: same `{ user, token }`
  /// parsing and connect, but reports through [AddServerOutcome] without
  /// publishing a global auth state.
  Future<AddServerOutcome> _completeAddServer(
    AccordServer server,
    Object? data,
  ) async {
    final parsed = _sessionFromAuthData(server, data);
    if (parsed.error != null) return AddServerOutcome.error(parsed.error!);
    if (data is Map && data['force_password_reset'] == true) {
      return AddServerOutcome.passwordReset(parsed.session!);
    }
    await _store.persist(parsed.session!);
    await _addConnection(parsed.session!, makeActive: true);
    return AddServerOutcome.ok();
  }

  /// Flips the active connection to [key] (a server already connected). No-op if
  /// [key] is not connected.
  void setActiveServer(String key) {
    if (!_connections.containsKey(key)) return;
    _makeActive(key);
  }
}
