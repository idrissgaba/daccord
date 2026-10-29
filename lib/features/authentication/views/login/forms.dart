part of '../accord_login.dart';

class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).textTheme.bodyMedium!.color!;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 30),
        SizedBox(
          width: 50,
          height: 50,
          child: CircularProgressIndicator(color: color),
        ),
      ],
    );
  }
}

class _AuthForm extends StatelessWidget {
  const _AuthForm({
    required this.serverController,
    required this.usernameController,
    required this.passwordController,
    required this.displayNameController,
    required this.mode,
    required this.hasAccounts,
    required this.tosAvailability,
    required this.tosAccepted,
    required this.onModeChanged,
    required this.onSwitchAccount,
    required this.onGeneratePassword,
    required this.onTosChanged,
    required this.onTosLinkTap,
    required this.onAppTermsTap,
    required this.onDiscover,
    required this.onSubmit,
    this.onBack,
    this.error,
  });

  final TextEditingController serverController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController displayNameController;
  final AuthMode mode;
  final bool hasAccounts;
  final TosAvailability tosAvailability;
  final bool tosAccepted;
  final VoidCallback? onBack;
  final ValueChanged<AuthMode> onModeChanged;
  final VoidCallback onSwitchAccount;
  final VoidCallback onGeneratePassword;
  final ValueChanged<bool> onTosChanged;
  final VoidCallback onTosLinkTap;

  /// Opens the app's own terms, linked under the submit button in both modes.
  final VoidCallback onAppTermsTap;
  final VoidCallback onDiscover;
  final VoidCallback onSubmit;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final isRegister = mode == AuthMode.register;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
          ),
        Text(
          'Welcome to Daccord',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Connect to your Accord server',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFC8C8C8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        AuthCredentialsFields(
          mode: mode,
          onModeChanged: onModeChanged,
          serverController: serverController,
          usernameController: usernameController,
          passwordController: passwordController,
          displayNameController: displayNameController,
          tosAvailability: tosAvailability,
          tosAccepted: tosAccepted,
          onTosChanged: onTosChanged,
          onTosLinkTap: onTosLinkTap,
          onGeneratePassword: onGeneratePassword,
          onSubmit: onSubmit,
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.red),
          ),
        ],
        const SizedBox(height: 24),
        _SubmitButton(
          label: isRegister ? 'Register' : 'Log In',
          onPressed: onSubmit,
        ),
        const SizedBox(height: 12),
        AppTermsNotice(onTap: onAppTermsTap),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: colors.darkGray)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: theme.textTheme.bodySmall),
            ),
            Expanded(child: Divider(color: colors.darkGray)),
          ],
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onDiscover,
          icon: const Icon(Icons.explore_outlined, size: 18),
          label: const Text('Discover public servers'),
        ),
        const SizedBox(height: 4),
        if (hasAccounts)
          TextButton(
            onPressed: onSwitchAccount,
            child: Text('Switch account', style: theme.textTheme.bodyMedium),
          ),
      ],
    );
  }
}

/// The signed-out server browser: a back affordance + the shared public-space
/// directory ([AccordDiscoveryBody]) shown full-screen, with a manual
/// connect-by-URL escape hatch. Joining a listing routes auth back through the
/// hosting login screen via [onJoinRequiresAuth].
class _BrowseView extends StatelessWidget {
  const _BrowseView({
    required this.onBack,
    required this.onManualConnect,
    required this.onJoinRequiresAuth,
  });

  final VoidCallback onBack;
  final VoidCallback onManualConnect;
  final void Function(String serverUrl, String spaceId) onJoinRequiresAuth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back, size: 20),
                  ),
                  Icon(Icons.explore, size: 20, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Discover Servers',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AccordDiscoveryBody(
                onJoinRequiresAuth: onJoinRequiresAuth,
                onManualConnect: onManualConnect,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MfaForm extends StatelessWidget {
  const _MfaForm({
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Two-factor authentication',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Enter the code from your authenticator app',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFC8C8C8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 32),
        AuthField(
          controller: controller,
          label: '6-digit code',
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          onSubmitted: (_) => onSubmit(),
        ),
        const SizedBox(height: 24),
        _SubmitButton(label: 'Verify', onPressed: onSubmit),
        const SizedBox(height: 8),
        TextButton(
          onPressed: onCancel,
          child: Text('Cancel', style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall!.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}
