import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/views/self_status_button.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bar at the foot of the channel column: who you are (avatar, status,
/// name — click for status, account switching and log out) and your mic,
/// headset and settings buttons, as in other voice chat apps.
class UserPanel extends ConsumerWidget {
  const UserPanel({
    super.key,
    required this.onOpenSettings,
    required this.onSwitchAccount,
    required this.onLogout,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onSwitchAccount;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final userId = ref.watchUserId();
    final serverKey = ref.watchActiveServerKey() ?? '';
    final user = userId == null
        ? null
        : ref.watch(
            accordUsersControllerProvider(
              serverKey,
            ).select((users) => users[userId]),
          );
    final status = ref.watch(
      activePresencesProvider.select(
        (p) => userId == null ? 'offline' : accordPresenceStatus(p, userId),
      ),
    );
    final customStatus = ref.watch(
      activePresencesProvider.select(
        (p) => userId == null ? null : accordCustomStatus(p, userId),
      ),
    );
    final name = accordUserName(user, fallback: userId ?? '');
    final subtitle = (customStatus?.isNotEmpty ?? false)
        ? customStatus!
        : user?.username ?? '';
    final voice = ref.watch(voiceControllerProvider);
    final voiceNotifier = ref.read(voiceControllerProvider.notifier);
    final muted = voice.selfMute || voice.selfDeaf;

    return Container(
      key: const Key('user-panel'),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Color.lerp(colors.foreground, colors.darkGray, 0.5),
      child: Row(
        children: [
          Expanded(
            child: SelfStatusButton(
              extras: [
                SelfStatusExtra(
                  label: 'Switch account',
                  icon: Icons.switch_account,
                  onSelected: onSwitchAccount,
                ),
                SelfStatusExtra(
                  label: 'Log out',
                  icon: Icons.logout,
                  onSelected: onLogout,
                  destructive: true,
                ),
              ],
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AccordMemberAvatar(
                        avatarUrl: user == null
                            ? null
                            : accordAvatarUrl(user, ref.watchCdnUrl()),
                        initial: accordInitial(name),
                        radius: 16,
                        backgroundColor: accordIdColor(userId ?? ''),
                        status: status,
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.dirtyWhite,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.gray,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _PanelButton(
            key: const Key('user-panel-mute'),
            tooltip: voice.selfMute ? 'Unmute' : 'Mute',
            icon: muted ? Icons.mic_off : Icons.mic,
            active: muted,
            onPressed: voiceNotifier.toggleMute,
          ),
          _PanelButton(
            key: const Key('user-panel-deafen'),
            tooltip: voice.selfDeaf ? 'Undeafen' : 'Deafen',
            icon: voice.selfDeaf ? Icons.headset_off : Icons.headset,
            active: voice.selfDeaf,
            onPressed: voiceNotifier.toggleDeafen,
          ),
          _PanelButton(
            key: const Key('user-panel-settings'),
            tooltip: 'User settings',
            icon: Icons.settings,
            active: false,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;

  /// Muted / deafened: drawn in red, as a warning.
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        icon,
        size: 20,
        color: active ? colors.red : colors.dirtyWhite,
      ),
    );
  }
}
