part of '../accord_account_settings.dart';

class _TwoFactorSection extends ConsumerStatefulWidget {
  const _TwoFactorSection({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  ConsumerState<_TwoFactorSection> createState() => _TwoFactorSectionState();
}

class _TwoFactorSectionState extends ConsumerState<_TwoFactorSection> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  // Set after a successful enable() call: the secret/otpauth the user must add
  // to their authenticator before verifying.
  String? _secret;
  String? _otpauth;
  List<String>? _backupCodes;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _enable() async {
    final client = ref.accordClient;
    if (client == null) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.auth.enable2fa({'password': _password.text});
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _busy = false;
      if (result.ok && data is Map) {
        _secret = data['secret']?.toString();
        _otpauth = data['otpauth_uri']?.toString() ?? data['uri']?.toString();
      } else {
        _error = result.errorOr('Failed to start 2FA setup');
      }
    });
  }

  Future<void> _verify() async {
    final client = ref.accordClient;
    if (client == null) return;
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.auth.verify2fa({'code': _code.text.trim()});
    if (!mounted) return;
    final data = result.data;
    setState(() {
      _busy = false;
      if (result.ok) {
        _backupCodes = data is Map && data['backup_codes'] is List
            ? (data['backup_codes'] as List).map((e) => e.toString()).toList()
            : null;
        _secret = null;
        _otpauth = null;
        _password.clear();
        _code.clear();
        widget.onChanged(true);
      } else {
        _error = result.errorOr('Invalid code');
      }
    });
  }

  Future<void> _disable() async {
    final client = ref.accordClient;
    if (client == null) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password to disable 2FA');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.auth.disable2fa({'password': _password.text});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result.ok) {
        _password.clear();
        _backupCodes = null;
        widget.onChanged(false);
      } else {
        _error = result.errorOr('Failed to disable 2FA');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_backupCodes != null) {
      return _BackupCodesView(codes: _backupCodes!);
    }

    if (widget.enabled) {
      return _TwoFactorEnabledView(
        password: _password,
        busy: _busy,
        error: _error,
        onDisable: _disable,
      );
    }

    return _TwoFactorSetupView(
      password: _password,
      code: _code,
      busy: _busy,
      error: _error,
      secret: _secret,
      otpauth: _otpauth,
      onEnable: _enable,
      onVerify: _verify,
    );
  }
}

/// Shown right after verification succeeds: the one-time backup codes with a
/// copy-to-clipboard shortcut.
class _BackupCodesView extends StatelessWidget {
  const _BackupCodesView({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '2FA is now enabled. Save these backup codes:',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.darkGray,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            codes.join('\n'),
            style: theme.textTheme.bodyMedium!.copyWith(fontFeatures: const []),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: codes.join('\n'))),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy codes'),
          ),
        ),
      ],
    );
  }
}

/// 2FA already on: password prompt + disable button.
class _TwoFactorEnabledView extends StatelessWidget {
  const _TwoFactorEnabledView({
    required this.password,
    required this.busy,
    required this.error,
    required this.onDisable,
  });

  final TextEditingController password;
  final bool busy;
  final String? error;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.verified_user, size: 18, color: colors.green),
            const SizedBox(width: 8),
            Text('2FA is enabled', style: theme.textTheme.bodyMedium),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: password,
          enabled: !busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          InlineError(error!, centered: false),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy ? null : onDisable,
            style: TextButton.styleFrom(foregroundColor: colors.red),
            child: const Text('Disable 2FA'),
          ),
        ),
      ],
    );
  }
}

/// Not yet enabled: either prompt for password (start), or show the secret +
/// verification field after enable() succeeded.
class _TwoFactorSetupView extends StatelessWidget {
  const _TwoFactorSetupView({
    required this.password,
    required this.code,
    required this.busy,
    required this.error,
    required this.secret,
    required this.otpauth,
    required this.onEnable,
    required this.onVerify,
  });

  final TextEditingController password;
  final TextEditingController code;
  final bool busy;
  final String? error;
  final String? secret;
  final String? otpauth;
  final VoidCallback onEnable;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final setupStarted = secret != null || otpauth != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!setupStarted) ...[
          Text(
            'Protect your account with an authenticator app.',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            InlineError(error!, centered: false),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: busy ? null : onEnable,
              child: const Text('Enable 2FA'),
            ),
          ),
        ] else ...[
          Text(
            'Scan this QR code with your authenticator app, or enter the '
            'secret manually, then type the 6-digit code:',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
          ),
          if (otpauth != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                // White quiet zone so scanners read the code regardless of theme.
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: otpauth!,
                  size: 180,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.darkGray,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    secret ?? extractTotpSecret(otpauth) ?? '',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy secret',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text: secret ?? extractTotpSecret(otpauth) ?? '',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: code,
            enabled: !busy,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!busy) onVerify();
            },
            decoration: const InputDecoration(
              labelText: '6-digit code',
              isDense: true,
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            InlineError(error!, centered: false),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: busy ? null : onVerify,
              child: const Text('Verify & activate'),
            ),
          ),
        ],
      ],
    );
  }
}
