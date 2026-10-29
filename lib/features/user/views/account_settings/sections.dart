part of '../accord_account_settings.dart';

/// Account-deletion section: password + type-to-confirm "DELETE", calling
/// `users.deleteMe` then removing the account locally. Mirrors the reference
/// client's `user_settings_danger.gd`.
class _DangerZoneSection extends ConsumerStatefulWidget {
  const _DangerZoneSection();

  @override
  ConsumerState<_DangerZoneSection> createState() => _DangerZoneSectionState();
}

class _DangerZoneSectionState extends ConsumerState<_DangerZoneSection> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final client = ref.accordClient;
    if (client == null || _busy) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Password is required');
      return;
    }
    if (_confirm.text.trim() != 'DELETE') {
      setState(() => _error = "Type DELETE to confirm");
      return;
    }
    final session = ref.read(accordAuthProvider);
    if (session is! AccordAuthLoggedIn) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await client.users.deleteMe({'password': _password.text});
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _busy = false;
        _error = result.errorOr('Failed to delete account');
      });
      return;
    }
    // Account gone server-side — drop it locally (switches to another server
    // or signs out when none remain).
    await ref.read(accordAuthProvider.notifier).removeAccount(session.session);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Permanently deletes your account on this server, including your '
          'profile, messages, and memberships. This cannot be undone.',
          style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirm,
          enabled: !_busy,
          decoration: const InputDecoration(
            isDense: true,
            labelText: "Type DELETE to confirm",
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          InlineError(_error!, centered: false),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _busy ? null : _delete,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_forever, size: 18),
            label: const Text('Delete my account'),
          ),
        ),
      ],
    );
  }
}

class _PasswordSection extends ConsumerStatefulWidget {
  const _PasswordSection();

  @override
  ConsumerState<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ConsumerState<_PasswordSection> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _success = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final client = ref.accordClient;
    if (client == null) return;
    final oldPw = _old.text;
    final newPw = _new.text;
    if (oldPw.isEmpty || newPw.length < 6) {
      setState(() {
        _success = false;
        _message = 'Enter your current password and a new one (6+ chars)';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await client.auth.changePassword({
      'old_password': oldPw,
      'new_password': newPw,
    });
    if (!mounted) return;
    setState(() {
      _busy = false;
      _success = result.ok;
      _message = result.ok
          ? 'Password updated'
          : result.errorOr('Failed to change password');
      if (result.ok) {
        _old.clear();
        _new.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _old,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Current password',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _new,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(
            _message!,
            style: theme.textTheme.bodySmall!.copyWith(
              color: _success ? colors.green : colors.red,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _submit,
            child: const Text('Change password'),
          ),
        ),
      ],
    );
  }
}
