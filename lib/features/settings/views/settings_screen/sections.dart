part of '../accord_settings_screen.dart';

/// Theme preset chips, accent-colour swatches, compact mode, emoticon
/// conversion, reduced motion, and the UI scale slider.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.settings, required this.controller});

  final AccordSettings settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Appearance'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in AppThemePreset.values)
                ChoiceChip(
                  label: Text(preset.label),
                  selected: settings.themePreset == preset,
                  onSelected: (_) => controller.setThemePreset(preset),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text(
            'Accent colour',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ColorSwatchChip(
                color: defaultAccentFor(settings.themePreset),
                selected: settings.accentColor == null,
                label: 'Default',
                onTap: () => controller.setAccentColor(null),
              ),
              for (final (argb, name) in avatarColorPalette)
                ColorSwatchChip(
                  color: Color(argb),
                  selected: settings.accentColor == argb,
                  label: name,
                  onTap: () => controller.setAccentColor(argb),
                ),
            ],
          ),
        ),
        if (UniversalPlatform.isWindows || UniversalPlatform.isLinux)
          SwitchListTile(
            key: const Key('settings-close-to-tray'),
            title: const Text('Minimize to tray when closing'),
            subtitle: const Text(
              'The close button keeps Daccord running in the system tray; '
              'quit from the tray icon',
            ),
            value: settings.closeToTray,
            onChanged: controller.setCloseToTray,
          ),
        SwitchListTile(
          title: const Text('Show embeds and link previews'),
          subtitle: const Text(
            'Hide previews only for you; message text stays visible',
          ),
          value: settings.showEmbeds,
          onChanged: controller.setShowEmbeds,
        ),
        SwitchListTile(
          title: const Text('Compact mode'),
          subtitle: const Text('Denser message layout (smaller spacing)'),
          value: settings.compactMode,
          onChanged: controller.setCompactMode,
        ),
        SwitchListTile(
          title: const Text('Convert emoticons to emoji'),
          subtitle: const Text('Turn :) and <3 into 🙂 and ❤️ as you send'),
          value: settings.convertEmoticons,
          onChanged: controller.setConvertEmoticons,
        ),
        SwitchListTile(
          key: const Key('settings-streamer-mode'),
          title: const Text('Streamer mode'),
          subtitle: const Text(
            'Hide your notes and invite codes and silence notifications '
            'while you stream or share your screen',
          ),
          value: settings.streamerMode,
          onChanged: controller.setStreamerMode,
        ),
        SwitchListTile(
          title: const Text('Reduced motion'),
          subtitle: const Text('Minimise UI animations'),
          value: settings.reducedMotion,
          onChanged: controller.setReducedMotion,
        ),
        ListTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('UI scale'),
              Text('${(settings.uiScale * 100).round()}%'),
            ],
          ),
          subtitle: Slider(
            value: settings.uiScale.clamp(
              AccordSettings.minUiScale,
              AccordSettings.maxUiScale,
            ),
            min: AccordSettings.minUiScale,
            max: AccordSettings.maxUiScale,
            divisions:
                ((AccordSettings.maxUiScale - AccordSettings.minUiScale) / 0.1)
                    .round(),
            label: '${(settings.uiScale * 100).round()}%',
            onChanged: controller.setUiScale,
          ),
        ),
      ],
    );
  }
}

/// Mention-notification toggles.
class _NotificationsSection extends StatelessWidget {
  const _NotificationsSection({
    required this.settings,
    required this.controller,
  });

  final AccordSettings settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Notifications'),
        SwitchListTile(
          title: const Text('Enable notifications'),
          subtitle: const Text('Show a system notification when mentioned'),
          value: settings.notificationsEnabled,
          onChanged: controller.setNotificationsEnabled,
        ),
        SwitchListTile(
          title: const Text('Suppress @everyone'),
          subtitle: const Text('Never notify for @everyone / @here mentions'),
          value: settings.suppressEveryone,
          onChanged: settings.notificationsEnabled
              ? controller.setSuppressEveryone
              : null,
        ),
        // Android sideload builds only — see [isBackgroundConnectionAvailable].
        // Without this entry the foreground service could not be turned on at
        // all, so the whole feature was unreachable from the UI (#306).
        if (isBackgroundConnectionAvailable)
          SwitchListTile(
            key: const Key('background-connection-switch'),
            title: const Text('Stay connected in the background'),
            subtitle: const Text(
              'Keeps notifications arriving while the app is closed. Shows a '
              'permanent notification and uses more battery.',
            ),
            value: settings.backgroundConnection,
            onChanged: controller.setBackgroundConnection,
          ),
      ],
    );
  }
}

/// SFX toggle + volume slider.
class _SoundsSection extends StatelessWidget {
  const _SoundsSection({required this.settings, required this.controller});

  final AccordSettings settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Sounds'),
        SwitchListTile(
          title: const Text('Enable sounds'),
          subtitle: const Text('Play SFX for messages and mentions'),
          value: settings.soundsEnabled,
          onChanged: controller.setSoundsEnabled,
        ),
        ListTile(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Volume'),
              Text('${(settings.sfxVolume * 100).round()}%'),
            ],
          ),
          subtitle: Slider(
            value: settings.sfxVolume,
            onChanged: settings.soundsEnabled ? controller.setSfxVolume : null,
          ),
        ),
      ],
    );
  }
}

/// Entry point into the dedicated voice & video settings screen.
class _VoiceVideoSection extends StatelessWidget {
  const _VoiceVideoSection();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Voice & Video'),
        ListTile(
          leading: Icon(Icons.mic_none, color: colors.dirtyWhite),
          title: const Text('Voice & video settings'),
          subtitle: const Text(
            'Microphone, speaker, sensitivity, camera, mic test',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showVoiceSettings(context),
        ),
      ],
    );
  }
}

/// Current session summary plus profile, security, account-switching,
/// connections, privacy, and (for admins) server administration entries.
class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.session,
    required this.hasMultipleConnections,
    required this.onPickServerProfile,
    this.showSubPageTiles = true,
  });

  final AccordSession? session;
  final bool hasMultipleConnections;
  final VoidCallback onPickServerProfile;

  /// Whether to include the Connections / Privacy & Data tiles that push their
  /// own sub-page. The wide layout renders both as sibling cards in the same
  /// pane instead, so it turns these off.
  final bool showSubPageTiles;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final session = this.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Account'),
        if (session != null)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colors.primary,
              child: Text(
                accordInitial(session.username),
                style: const TextStyle(color: Colors.white),
              ),
            ),
            title: Text(session.username),
            subtitle: Text(session.server.baseUrl),
          ),
        ListTile(
          leading: Icon(Icons.edit_outlined, color: colors.dirtyWhite),
          title: const Text('Edit profile'),
          subtitle: const Text('Display name, bio, avatar'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showAccordProfileEdit(context),
        ),
        ListTile(
          leading: Icon(Icons.lock_outline, color: colors.dirtyWhite),
          title: const Text('Password & Security'),
          subtitle: const Text(
            'Password, two-factor authentication, delete account',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showAccordAccountSettings(context),
        ),
        if (hasMultipleConnections)
          ListTile(
            leading: Icon(Icons.dns_outlined, color: colors.dirtyWhite),
            title: const Text('Per-server profile'),
            subtitle: const Text("Override name/bio/avatar on one server"),
            trailing: const Icon(Icons.chevron_right),
            onTap: onPickServerProfile,
          ),
        ListTile(
          leading: Icon(Icons.switch_account, color: colors.dirtyWhite),
          title: const Text('Switch account'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/switcher'),
        ),
        ListTile(
          leading: Icon(Icons.devices, color: colors.dirtyWhite),
          title: const Text('Device profiles'),
          subtitle: const Text(
            'Local profiles with an optional casual PIN lock',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showProfilesSettings(context),
        ),
        if (showSubPageTiles) ...[
          ListTile(
            leading: Icon(Icons.link, color: colors.dirtyWhite),
            title: const Text('Connections'),
            subtitle: const Text('Linked third-party (OAuth) accounts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showConnectionsSettings(context),
          ),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: colors.dirtyWhite),
            title: const Text('Privacy & Data'),
            subtitle: const Text('Data export, leave & delete data, retention'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showPrivacySettings(context),
          ),
        ],
        if (session?.isAdmin ?? false)
          ListTile(
            leading: Icon(Icons.admin_panel_settings, color: colors.dirtyWhite),
            title: const Text('Server administration'),
            subtitle: const Text('Spaces, users, reports, settings'),
            onTap: () => context.push('/admin'),
          ),
      ],
    );
  }
}

/// Master-server directory URL used to browse public spaces.
class _ServerDirectorySection extends StatelessWidget {
  const _ServerDirectorySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Server Directory'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: _MasterServerField(),
        ),
      ],
    );
  }
}

/// Entry point into the updates / release-check page.
class _UpdatesSection extends StatelessWidget {
  const _UpdatesSection();

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Updates'),
        ListTile(
          leading: Icon(Icons.system_update, color: colors.dirtyWhite),
          title: const Text('Updates'),
          subtitle: const Text('Current version, check for new releases'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showUpdatesSettings(context),
        ),
      ],
    );
  }
}

/// Settings export/import.
class _BackupSection extends StatelessWidget {
  const _BackupSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionHeader('Backup'), const SettingsBackupSection()],
    );
  }
}

/// Developer-mode toggle and the Client MCP server page it unlocks.
class _DeveloperSection extends StatelessWidget {
  const _DeveloperSection({required this.settings, required this.controller});

  final AccordSettings settings;
  final SettingsController controller;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('Developer'),
        SwitchListTile(
          title: const Text('Developer Mode'),
          subtitle: const Text(
            'Unlock the local Client MCP server for AI agents',
          ),
          value: settings.developerMode,
          onChanged: controller.setDeveloperMode,
        ),
        if (settings.developerMode)
          ListTile(
            leading: Icon(Icons.terminal, color: colors.dirtyWhite),
            title: const Text('Client MCP server'),
            subtitle: const Text('Token, port, tool groups, activity'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDeveloperSettings(context),
          ),
      ],
    );
  }
}

/// App name, licence, and version.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('About'),
        ListTile(
          title: const Text('Daccord'),
          subtitle: const Text(
            'A native multi-platform Daccord client (GPLv3).',
          ),
          trailing: Text('v$kAppVersion'),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: const Text(appTermsTitle),
          subtitle: const Text(
            'The terms you accepted, including what is not allowed and how to '
            'report it.',
          ),
          onTap: () => showAppTermsDialog(context),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy Policy'),
          subtitle: const Text(
            'How the app, website, and independent servers handle data.',
          ),
          trailing: const Icon(Icons.open_in_new, size: 16),
          onTap: () => openTrustedUrl(kDaccordPrivacyPolicyUrl),
        ),
      ],
    );
  }
}

/// Signs the current account out and returns to the entry route.
class _LogOutTile extends StatelessWidget {
  const _LogOutTile({required this.onLogOut});

  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return ListTile(
      leading: Icon(Icons.logout, color: colors.red),
      title: Text('Log out', style: TextStyle(color: colors.red)),
      onTap: onLogOut,
    );
  }
}

/// Lets the user pick which connected server's profile to edit, then opens the
/// per-server profile editor for it.
Future<void> _pickServerProfile(BuildContext context, WidgetRef ref) async {
  final connections = ref.read(connectionsControllerProvider).connections;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final conn in connections)
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(
                conn.session.server.name ?? conn.session.server.baseUrl,
              ),
              subtitle: Text(conn.session.username),
              onTap: () {
                Navigator.of(ctx).pop();
                showAccordProfileEdit(context, serverKey: conn.key);
              },
            ),
        ],
      ),
    ),
  );
}

/// Editable master-server directory URL (default https://master.daccord.gg),
/// used to browse public spaces without an account.
class _MasterServerField extends ConsumerStatefulWidget {
  const _MasterServerField();

  @override
  ConsumerState<_MasterServerField> createState() => _MasterServerFieldState();
}

class _MasterServerFieldState extends ConsumerState<_MasterServerField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(settingsControllerProvider).masterServerUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref
        .read(settingsControllerProvider.notifier)
        .setMasterServerUrl(_controller.text);
    final applied = ref.read(settingsControllerProvider).masterServerUrl;
    _controller.text = applied;
    FocusScope.of(context).unfocus();
    showInfoSnack(context, 'Master server URL saved');
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Master server URL',
              hintText: AccordSettings.defaultMasterServerUrl,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
