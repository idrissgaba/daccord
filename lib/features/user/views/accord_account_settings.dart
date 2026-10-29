import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/dialog_title_bar.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

part 'account_settings/sections.dart';

part 'account_settings/two_factor.dart';

/// Extracts the bare TOTP secret from an `otpauth://` URI, or returns the
/// input unchanged when it is not an otpauth URI (e.g. already a plain secret).
///
/// `otpauth://totp/label?secret=BASE32SECRET&issuer=…` → `BASE32SECRET`
String? extractTotpSecret(String? uri) {
  if (uri == null) return null;
  final match = RegExp(
    r'[?&]secret=([^&]+)',
    caseSensitive: false,
  ).firstMatch(uri);
  return match?.group(1) ?? uri;
}

/// Opens the account settings dialog: change password and manage two-factor
/// authentication.
Future<void> showAccordAccountSettings(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AccountSettingsDialog(),
  );
}

class _AccountSettingsDialog extends ConsumerStatefulWidget {
  const _AccountSettingsDialog();

  @override
  ConsumerState<_AccountSettingsDialog> createState() =>
      _AccountSettingsDialogState();
}

class _AccountSettingsDialogState
    extends ConsumerState<_AccountSettingsDialog> {
  bool? _mfaEnabled;

  @override
  void initState() {
    super.initState();
    _loadMfaState();
  }

  Future<void> _loadMfaState() async {
    final client = ref.accordClient;
    if (client == null) return;
    final result = await client.users.getMe();
    if (!mounted) return;
    final user = result.data;
    setState(() {
      _mfaEnabled = user is AccordUser ? user.mfaEnabled : false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 460, maxHeight: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DialogTitleBar('Password & Security'),
              const SizedBox(height: 12),
              Text(
                'PASSWORD',
                style: theme.textTheme.labelSmall!.copyWith(
                  color: colors.gray,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const _PasswordSection(),
              const SizedBox(height: 20),
              Divider(height: 1, color: colors.background),
              const SizedBox(height: 16),
              Text(
                'TWO-FACTOR AUTHENTICATION',
                style: theme.textTheme.labelSmall!.copyWith(
                  color: colors.gray,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (_mfaEnabled == null)
                const Padding(padding: EdgeInsets.all(8), child: LoadingView())
              else
                _TwoFactorSection(
                  enabled: _mfaEnabled!,
                  onChanged: (v) => setState(() => _mfaEnabled = v),
                ),
              const SizedBox(height: 20),
              Divider(height: 1, color: colors.background),
              const SizedBox(height: 16),
              Text(
                'DANGER ZONE',
                style: theme.textTheme.labelSmall!.copyWith(
                  color: colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const _DangerZoneSection(),
            ],
          ),
        ),
      ),
    );
  }
}
