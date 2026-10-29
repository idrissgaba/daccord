import 'dart:async';

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/credential_validation.dart';
import 'package:bonfire/features/authentication/utils/terms_acceptance.dart';
import 'package:bonfire/features/authentication/utils/tos_gate.dart';
import 'package:bonfire/features/authentication/views/auth_form.dart';
import 'package:bonfire/features/authentication/views/password_reset_form.dart';
import 'package:bonfire/features/authentication/views/terms_gate.dart';
import 'package:bonfire/features/authentication/views/welcome_view.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/services/deep_link_navigation.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'login/forms.dart';

/// Server-URL + credentials login against an Accord server. Drives
/// [accordAuthProvider] (restore-on-launch → sign in / register → optional MFA
/// or forced password change → connect) and, once a live session exists, hands
/// off to the messaging frame.
///
/// [initialMode] selects the Sign in / Register tab on entry; the `/register`
/// route uses it to land directly on registration.
///
/// [startOnCredentials] skips the welcome → browser onboarding and lands
/// directly on the connect-by-URL credentials form. The `/login` and `/register`
/// routes set it so deep links and "add another account" go straight to the
/// form, while the default `/` route opens onboarding.
class AccordLoginScreen extends ConsumerStatefulWidget {
  const AccordLoginScreen({
    super.key,
    this.initialMode = AuthMode.signIn,
    this.startOnCredentials = false,
  });

  final AuthMode initialMode;
  final bool startOnCredentials;

  @override
  ConsumerState<AccordLoginScreen> createState() => _AccordLoginScreenState();
}

/// The signed-out sub-flow: branded onboarding → public server browser → the
/// credentials form for the chosen instance.
enum _LoggedOutView { welcome, browse, credentials }

class _AccordLoginScreenState extends ConsumerState<AccordLoginScreen> {
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _mfaController = TextEditingController();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late AuthMode _mode = widget.initialMode;

  /// Which signed-out sub-view is showing. Defaults to onboarding unless the
  /// route asked to land on the credentials form.
  late _LoggedOutView _view = widget.startOnCredentials
      ? _LoggedOutView.credentials
      : _LoggedOutView.welcome;

  /// A space chosen from discovery while signed out: once the credentials in
  /// this form authenticate, we join it before handing off to the frame.
  String? _pendingJoinSpaceId;

  /// Client-side validation error for the password-change form.
  String? _resetLocalError;

  /// Client-side validation error for the credentials form (e.g. unaccepted ToS
  /// or too-short registration password).
  String? _authLocalError;

  /// Whether any saved accounts exist, gating the "switch account" link.
  bool _hasAccounts = false;

  /// Whether the app's own terms have been accepted on this device. Until they
  /// are, the gate replaces the whole signed-out flow: App Review 1.2 requires
  /// the EULA before either registration or sign-in.
  bool _termsAccepted = true;

  // Terms-of-Service config, fetched per server when the Register tab is shown.
  TosConfig _tos = tosNotFetched;
  bool _tosAccepted = false;
  String? _tosFetchedServer;

  /// True until the launch-time session restore attempt settles, so we show a
  /// loader instead of flashing the login form for returning users.
  bool _restoring = true;
  bool _lookingUpAccount = false;
  bool _finishingLogin = false;

  @override
  void initState() {
    super.initState();
    _termsAccepted = hasAcceptedAppTerms();
    final lastServer = ProfileStore.sessionBox.get('last-server');
    if (lastServer is String) _serverController.text = lastServer;
    final pending = ref.read(pendingServerJoinProvider);
    final pendingServer = pending?.server;
    if (pendingServer != null) {
      _serverController.text = pendingServer.baseUrl;
      _view = _LoggedOutView.credentials;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(accordAuthProvider.notifier);
      final accounts = await notifier.listAccounts();
      if (mounted) setState(() => _hasAccounts = accounts.isNotEmpty);

      // Don't re-restore over a live session (e.g. when arriving here to add
      // another account from the switcher).
      if (ref.read(accordAuthProvider) is! AccordAuthLoggedIn) {
        await notifier.restoreSession();
      }
      if (mounted) setState(() => _restoring = false);

      // Landed straight on the Register tab (via /register): fetch the ToS gate.
      if (_mode == AuthMode.register) _fetchTos();
    });
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _mfaController.dispose();
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onModeChanged(AuthMode mode) {
    setState(() {
      _mode = mode;
      _authLocalError = null;
    });
    if (mode == AuthMode.register) _fetchTos();
  }

  AccordServer? _serverFromInput(String raw) {
    try {
      return AccordServer.fromBaseUrl(raw);
    } on FormatException catch (error) {
      if (mounted) setState(() => _authLocalError = error.message);
      return null;
    }
  }

  Future<void> _fetchTos() async {
    final raw = _serverController.text.trim();
    if (raw.isEmpty) return;
    final server = _serverFromInput(raw);
    if (server == null) return;
    if (_tosFetchedServer == server.baseUrl) return;
    final tos = await fetchTosConfig(
      ref.read(accordAuthProvider.notifier),
      server,
    );
    if (!mounted) return;
    setState(() {
      _tosFetchedServer = server.baseUrl;
      _tos = tos;
      _tosAccepted = false;
    });
  }

  void _generatePassword() {
    _passwordController.text = generateAuthPassword();
  }

  /// Accepts the app's terms: the gate lifts immediately and the record is
  /// written behind it. A failed write only means the gate shows again next
  /// launch, which is the right way for this to fail.
  void _acceptAppTerms() {
    setState(() => _termsAccepted = true);
    unawaited(recordAppTermsAcceptance());
  }

  /// Discovery (the embedded browser while signed out) needs auth against
  /// `serverUrl` before joining `spaceId`: switch to the credentials form,
  /// pre-fill it, and remember the space so the next successful login joins it.
  void _onDiscoveryJoinRequiresAuth(String serverUrl, String spaceId) {
    ref
        .read(pendingServerJoinProvider.notifier)
        .hold(
          ParsedServerUrl(
            server: AccordServer.fromBaseUrl(serverUrl),
            spaceId: spaceId,
          ),
        );
    ProfileStore.sessionBox.put('last-server', serverUrl);
    setState(() {
      _serverController.text = serverUrl;
      _pendingJoinSpaceId = spaceId;
      _mode = AuthMode.signIn;
      _authLocalError = null;
      _view = _LoggedOutView.credentials;
    });
  }

  Future<void> _submit() async {
    if (_lookingUpAccount) return;
    final rawServer = _serverController.text.trim();
    if (rawServer.isEmpty) return;
    final parsed = ServerUri.parseServerUrl(rawServer);
    final server = parsed?.server;
    if (parsed == null || server == null) {
      setState(() => _authLocalError = 'Enter a valid server URL');
      return;
    }
    final pending = ref.read(pendingServerJoinProvider);
    if (parsed.hasInvite ||
        parsed.spaceName != null ||
        pending == null ||
        pending.server == null ||
        !AccordServer.sameEndpoint(pending.server!.baseUrl, server.baseUrl)) {
      ref.read(pendingServerJoinProvider.notifier).hold(parsed);
    }
    ProfileStore.sessionBox.put('last-server', server.baseUrl);
    final notifier = ref.read(accordAuthProvider.notifier);
    setState(() => _lookingUpAccount = true);
    try {
      final key = await notifier.ensureConnectionForBaseUrl(server.baseUrl);
      if (!mounted) return;
      if (key != null) {
        notifier.setActiveServer(key);
        return;
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _authLocalError = 'Could not use the saved account: $error',
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _lookingUpAccount = false);
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    if (_mode == AuthMode.register) {
      final validationError = validateRegistrationCredentials(
        username: username,
        password: password,
        tosRequired: _tos.availability == TosAvailability.advertised,
        tosAccepted: _tosAccepted,
      );
      if (validationError != null) {
        setState(() => _authLocalError = validationError);
        return;
      }
      setState(() => _authLocalError = null);
      // An invite link for this server lets an invite-only server admit us.
      final pending = ref.read(pendingServerJoinProvider);
      final invite =
          pending?.server != null &&
              AccordServer.sameEndpoint(
                pending!.server!.baseUrl,
                server.baseUrl,
              )
          ? pending.invite
          : null;
      notifier.registerWithCredentials(
        server: server,
        username: username,
        password: password,
        displayName: _displayNameController.text.trim(),
        inviteCode: invite,
      );
    } else {
      setState(() => _authLocalError = null);
      notifier.loginWithCredentials(
        server: server,
        username: username,
        password: password,
      );
    }
  }

  void _submitMfa() {
    final code = _mfaController.text.trim();
    if (code.isEmpty) return;
    ref.read(accordAuthProvider.notifier).submitMfa(code);
  }

  void _submitPasswordChange() {
    final oldPw = _oldPasswordController.text;
    final newPw = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    final validationError = validatePasswordChangeCredentials(
      oldPassword: oldPw,
      newPassword: newPw,
      confirmation: confirm,
    );
    if (validationError != null) {
      setState(() => _resetLocalError = validationError);
      return;
    }
    setState(() => _resetLocalError = null);
    ref
        .read(accordAuthProvider.notifier)
        .submitPasswordChange(oldPassword: oldPw, newPassword: newPw);
  }

  Future<void> _finishLogin(AccordAuthLoggedIn loggedIn) async {
    if (_finishingLogin) return;
    _finishingLogin = true;
    final pending = ref.read(pendingServerJoinProvider);
    if (pending != null &&
        pending.server != null &&
        AccordServer.sameEndpoint(
          pending.server!.baseUrl,
          loggedIn.session.server.baseUrl,
        )) {
      try {
        final outcome = await ref
            .read(accordAuthProvider.notifier)
            .joinOnConnection(
              loggedIn.session.key,
              spaceId: pending.spaceId ?? pending.spaceName,
              invite: pending.invite,
            );
        if (!mounted) return;
        if (outcome.error != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(outcome.error!)));
        } else {
          // A newer link may have arrived while this join was in flight.
          if (identical(ref.read(pendingServerJoinProvider), pending)) {
            ref.read(pendingServerJoinProvider.notifier).clear();
          }
          final destination = outcome.spaceId == null
              ? (pending.spaceName != null || pending.channelName != null
                    ? PendingDeepLinkDestination.fromParsed(pending)
                    : null)
              : PendingDeepLinkDestination(
                  serverBaseUrl: loggedIn.session.server.baseUrl,
                  spaceId: outcome.spaceId,
                  channelName: pending.channelName,
                );
          if (destination != null) {
            ref.read(pendingDeepLinkProvider.notifier).hold(destination);
          }
        }
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not join: $error')));
      }
    }
    if (!mounted) return;
    _pendingJoinSpaceId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(pendingDeepLinkProvider) == null) {
        context.go('/spaces');
      }
    });
    _finishingLogin = false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accordAuthProvider);
    ref.listen(pendingServerJoinProvider, (previous, next) {
      final server = next?.server;
      if (server == null) return;
      setState(() {
        _serverController.text = server.baseUrl;
        _view = _LoggedOutView.credentials;
      });
    });

    // Covers a login that completes *while this screen is showing* — a state
    // change doesn't re-run router redirects. Arriving already logged in is
    // redirected home by `redirectLoggedInToHome` before this ever builds.
    ref.listen(accordAuthProvider, (previous, next) {
      if (next is AccordAuthLoggedIn) {
        _finishLogin(next);
      }
    });

    // Loading / MFA / forced-password-change: simple centered forms with no
    // onboarding chrome.
    if (_restoring ||
        _lookingUpAccount ||
        state is AccordAuthInProgress ||
        state is AccordAuthLoggedIn) {
      return _centered(
        _Loading(label: _restoring ? 'Reconnecting…' : 'Signing in…'),
      );
    }
    if (state is AccordAuthMfaRequired) {
      return _centered(
        _MfaForm(
          controller: _mfaController,
          onSubmit: _submitMfa,
          onCancel: () => ref.read(accordAuthProvider.notifier).logout(),
        ),
      );
    }
    if (state is AccordAuthPasswordResetRequired) {
      return _centered(
        PasswordResetForm(
          oldController: _oldPasswordController,
          newController: _newPasswordController,
          confirmController: _confirmPasswordController,
          onSubmit: _submitPasswordChange,
          onCancel: () => ref.read(accordAuthProvider.notifier).logout(),
          error: _resetLocalError ?? state.error,
        ),
      );
    }

    // Nothing in the signed-out flow — not the welcome screen, not the server
    // browser, and above all not the credentials form — is reachable before the
    // terms are accepted.
    if (!_termsAccepted) {
      return _centered(TermsGateView(onAccept: _acceptAppTerms), maxWidth: 560);
    }

    // Signed out: walk welcome → browse → credentials. Intercept system back to
    // step through the sub-flow rather than leaving the screen, except at the
    // flow's entry view.
    final Widget signedOut = switch (_view) {
      _LoggedOutView.welcome => _centered(
        WelcomeView(
          onBrowse: () => setState(() => _view = _LoggedOutView.browse),
          onManualConnect: () =>
              setState(() => _view = _LoggedOutView.credentials),
          onSwitchAccount: _hasAccounts
              ? () => context.push('/switcher')
              : null,
        ),
        // Wide enough for the welcome screen's three-up highlights on a tablet
        // or desktop canvas; it collapses itself back to a phone layout below
        // `kWelcomeWideBreakpoint`.
        maxWidth: 760,
      ),
      _LoggedOutView.browse => _BrowseView(
        onBack: _goBack,
        onManualConnect: () =>
            setState(() => _view = _LoggedOutView.credentials),
        onJoinRequiresAuth: _onDiscoveryJoinRequiresAuth,
      ),
      _LoggedOutView.credentials => _centered(
        _AuthForm(
          serverController: _serverController,
          usernameController: _usernameController,
          passwordController: _passwordController,
          displayNameController: _displayNameController,
          mode: _mode,
          hasAccounts: _hasAccounts,
          tosAvailability: _tos.availability,
          tosAccepted: _tosAccepted,
          onBack: _atFlowRoot ? null : _goBack,
          onModeChanged: _onModeChanged,
          onSwitchAccount: () => context.push('/switcher'),
          onGeneratePassword: _generatePassword,
          onTosChanged: (v) => setState(() => _tosAccepted = v),
          onTosLinkTap: () => openTos(context, _tos),
          onAppTermsTap: () => showAppTermsDialog(context),
          onDiscover: () => setState(() => _view = _LoggedOutView.browse),
          onSubmit: _submit,
          error:
              _authLocalError ??
              (state is AccordAuthFailed ? state.message : null),
        ),
      ),
    };

    return PopScope(
      canPop: _atFlowRoot,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: signedOut,
    );
  }

  Widget _centered(Widget child, {double maxWidth = 420}) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: child,
          ),
        ),
      ),
    );
  }

  /// The signed-out view from which a back gesture should leave the screen
  /// rather than step back through the onboarding sub-flow.
  bool get _atFlowRoot =>
      _view == _LoggedOutView.welcome ||
      (widget.startOnCredentials && _view == _LoggedOutView.credentials);

  void _goBack() {
    setState(() {
      if (_view == _LoggedOutView.browse) {
        _view = widget.startOnCredentials
            ? _LoggedOutView.credentials
            : _LoggedOutView.welcome;
      } else if (_view == _LoggedOutView.credentials) {
        _view = _pendingJoinSpaceId != null
            ? _LoggedOutView.browse
            : _LoggedOutView.welcome;
        _pendingJoinSpaceId = null;
        _authLocalError = null;
      }
    });
  }
}
