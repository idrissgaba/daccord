import 'package:universal_platform/universal_platform.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/shared/components/color_swatch_chip.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/utils/confirm_logout.dart';
import 'package:bonfire/features/developer/views/developer_settings_page.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/profiles/views/profiles_page.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/views/connections_settings_page.dart';
import 'package:bonfire/features/settings/views/keybinds_section.dart';
import 'package:bonfire/features/settings/views/privacy_settings_page.dart';
import 'package:bonfire/features/settings/views/settings_backup.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/onboarding/views/onboarding_tour.dart';
import 'package:bonfire/features/updates/views/updates_page.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/views/accord_account_settings.dart';
import 'package:bonfire/features/user/views/accord_profile_edit.dart';
import 'package:bonfire/features/authentication/models/app_terms.dart';
import 'package:bonfire/features/authentication/views/terms_gate.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

part 'settings_screen/sections.dart';

/// Client settings: appearance (theme preset + accent), notifications, account.
///
/// Two layouts share the same section widgets:
///
/// * **Narrow** (< [kSettingsWideBreakpoint]) — the original single flat
///   `ListView` of all eleven sections. Unchanged.
/// * **Wide** — a left category sidebar (Account / App / System / Advanced)
///   plus one ordered, width-capped content column. See [_DesktopSettings].
class AccordSettingsScreen extends ConsumerWidget {
  const AccordSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final session = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session : null,
      ),
    );

    Future<void> logOut() async {
      if (!await confirmLogout(context)) return;
      if (!context.mounted) return;
      ref.read(accordAuthProvider.notifier).logout();
      if (context.mounted) context.go('/');
    }

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.foreground,
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/spaces'),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= kSettingsWideBreakpoint) {
            return _DesktopSettings(onLogOut: logOut);
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _AppearanceSection(settings: settings, controller: controller),
              const Divider(height: 24),
              _NotificationsSection(settings: settings, controller: controller),
              const Divider(height: 24),
              _SoundsSection(settings: settings, controller: controller),
              const Divider(height: 24),
              const _VoiceVideoSection(),
              const Divider(height: 24),
              const KeybindsSection(),
              const Divider(height: 24),
              _AccountSection(
                session: session,
                hasMultipleConnections: ref
                    .watch(connectionsControllerProvider)
                    .hasMultiple,
                onPickServerProfile: () => _pickServerProfile(context, ref),
              ),
              const Divider(height: 24),
              const _ServerDirectorySection(),
              const Divider(height: 24),
              // Store builds update through the store and never expose the
              // GitHub self-updater; Developer Mode is desktop-only (#292).
              if (isSelfUpdateEnabled) ...[
                const _UpdatesSection(),
                const Divider(height: 24),
              ],
              const _BackupSection(),
              const Divider(height: 24),
              if (isDeveloperModeAvailable) ...[
                _DeveloperSection(settings: settings, controller: controller),
                const Divider(height: 24),
              ],
              const OnboardingHelpSection(),
              const Divider(height: 24),
              const _AboutSection(),
              const Divider(height: 24),
              _LogOutTile(onLogOut: logOut),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wide (desktop) layout
// ---------------------------------------------------------------------------

/// Width at which the settings screen swaps the flat scroll for the sidebar +
/// multi-column pane.
///
/// Deliberately *not* `shouldUseDesktopLayout`: that helper also requires
/// height > 1000, so it is false on short-but-wide desktop windows — exactly
/// the shape that needs a multi-column settings layout most. Column count is a
/// pure function of width, so it is measured with a width-only breakpoint.
const double kSettingsWideBreakpoint = 1000;

/// Maximum width of the ordered settings content. Caps every control row so a label and
/// its switch stay visually paired instead of sitting at opposite ends of an
/// ultrawide window.
const double kSettingsContentMaxWidth = 760;

const double _kSidebarWidth = 232;
const double _kPanePadding = 16;

/// The sidebar categories the settings sections group into.
enum SettingsCategory {
  account('Account', Icons.person_outline),
  app('App', Icons.tune),
  keybinds('Keybinds', Icons.keyboard_outlined),
  system('System', Icons.settings_applications_outlined),
  advanced('Advanced', Icons.code);

  const SettingsCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Sidebar + content pane. Owns which category is selected.
class _DesktopSettings extends StatefulWidget {
  const _DesktopSettings({required this.onLogOut});

  final VoidCallback onLogOut;

  @override
  State<_DesktopSettings> createState() => _DesktopSettingsState();
}

class _DesktopSettingsState extends State<_DesktopSettings> {
  SettingsCategory _selected = SettingsCategory.account;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CategorySidebar(
          selected: _selected,
          onSelect: (category) => setState(() => _selected = category),
          onLogOut: widget.onLogOut,
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.background),
        Expanded(child: _CategoryPane(category: _selected)),
      ],
    );
  }
}

/// Fixed-width category list, with Log out pinned to the bottom so it stays
/// reachable from every category.
class _CategorySidebar extends StatelessWidget {
  const _CategorySidebar({
    required this.selected,
    required this.onSelect,
    required this.onLogOut,
  });

  final SettingsCategory selected;
  final ValueChanged<SettingsCategory> onSelect;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Material(
      key: const ValueKey('settings-sidebar'),
      color: colors.foreground,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: SizedBox(
          width: _kSidebarWidth,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final category in SettingsCategory.values)
                      FocusTraversalOrder(
                        key: ValueKey('settings-category-${category.name}'),
                        order: NumericFocusOrder(category.index.toDouble()),
                        child: _SidebarTile(
                          category: category,
                          selected: category == selected,
                          onTap: () => onSelect(category),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: colors.background),
              FocusTraversalOrder(
                order: const NumericFocusOrder(100),
                child: _LogOutTile(onLogOut: onLogOut),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: colors.primary.withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(
          category.icon,
          size: 20,
          color: selected ? colors.primary : colors.dirtyWhite,
        ),
        title: Text(
          category.label,
          style: TextStyle(color: selected ? colors.primary : null),
        ),
        onTap: onTap,
      ),
    );
  }
}

/// The selected category's sections in one predictable top-to-bottom sequence.
/// Unequal sections retain their natural visual weight instead of each becoming
/// an equal card or being distributed round-robin across columns.
class _CategoryPane extends ConsumerWidget {
  const _CategoryPane({required this.category});

  final SettingsCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final session = ref.watch(
      accordAuthProvider.select(
        (s) => s is AccordAuthLoggedIn ? s.session : null,
      ),
    );

    final sections = switch (category) {
      SettingsCategory.account => <Widget>[
        _AccountSection(
          session: session,
          hasMultipleConnections: ref
              .watch(connectionsControllerProvider)
              .hasMultiple,
          onPickServerProfile: () => _pickServerProfile(context, ref),
          // Connections and Privacy & Data are cards in this same pane, so
          // their "push a sub-page" tiles would be redundant here.
          showSubPageTiles: false,
        ),
        const ConnectionsScreen(embedded: true),
        const PrivacySettingsScreen(embedded: true),
        const _ServerDirectorySection(),
      ],
      SettingsCategory.app => <Widget>[
        _AppearanceSection(settings: settings, controller: controller),
        _NotificationsSection(settings: settings, controller: controller),
        _SoundsSection(settings: settings, controller: controller),
        const _VoiceVideoSection(),
      ],
      SettingsCategory.keybinds => <Widget>[const KeybindsSection()],
      SettingsCategory.system => <Widget>[
        // Store builds update through the store and never expose the GitHub
        // self-updater (#292).
        if (isSelfUpdateEnabled) const _UpdatesSection(),
        const _BackupSection(),
      ],
      SettingsCategory.advanced => <Widget>[
        // The local MCP server is desktop-only and never in a store build.
        if (isDeveloperModeAvailable)
          _DeveloperSection(settings: settings, controller: controller),
        const OnboardingHelpSection(),
        const _AboutSection(),
      ],
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        _kPanePadding,
        _kPanePadding,
        _kPanePadding,
        32,
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kSettingsContentMaxWidth),
          child: Column(
            key: const ValueKey('settings-content-column'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) const Divider(height: 32),
                sections[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
