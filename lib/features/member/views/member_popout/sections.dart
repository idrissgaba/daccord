part of '../accord_member_popout.dart';

/// The top row of the popout: avatar with presence dot, display name (in the
/// member's color role), @username, presence label, custom status, and the
/// remote-origin badge for federated users.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.avatarBackgroundColor,
    required this.status,
    required this.nameColor,
    required this.customStatus,
    required this.remoteDomain,
  });

  final String name;
  final String? username;
  final String? avatarUrl;
  final Color avatarBackgroundColor;
  final String status;
  final Color? nameColor;
  final String? customStatus;
  final String? remoteDomain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Row(
      children: [
        AccordMemberAvatar(
          avatarUrl: avatarUrl,
          initial: accordInitial(name),
          status: status,
          radius: 28,
          backgroundColor: avatarBackgroundColor,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: theme.textTheme.titleMedium!.copyWith(color: nameColor),
                overflow: TextOverflow.ellipsis,
              ),
              if (username != null)
                Text(
                  '@$username',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.gray,
                  ),
                ),
              Text(
                _statusLabel(status),
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
              if (customStatus != null) ...[
                const SizedBox(height: 2),
                Text(
                  customStatus!,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.dirtyWhite,
                  ),
                ),
              ],
              if (remoteDomain != null) ...[
                const SizedBox(height: 4),
                RemoteOriginBadge(domain: remoteDomain!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'online':
        return 'Online';
      case 'idle':
        return 'Idle';
      case 'dnd':
        return 'Do Not Disturb';
      default:
        return 'Offline';
    }
  }
}

/// The amber "Timed out until …" pill shown while a member is timed out.
class _TimeoutBanner extends StatelessWidget {
  const _TimeoutBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFAA81A).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFFAA81A)),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// The read-only membership facts: "Member since" date and the member's
/// current role chips.
class _MembershipInfo extends StatelessWidget {
  const _MembershipInfo({
    required this.member,
    required this.roles,
    required this.memberRoleIds,
  });

  final AccordMember member;
  final List<AccordRole> roles;
  final List<String> memberRoleIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (member.joinedAt.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Member since ${_date(member.joinedAt)}',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
          ),
        ],
        if (memberRoleIds.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'ROLES',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in memberRoleIds)
                if (roles.firstWhereOrNull((r) => r.id == id) case final role?)
                  _RoleChip(role: role),
            ],
          ),
        ],
      ],
    );
  }

  String _date(String iso) {
    final dt = parseServerTimestamp(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final AccordRole role;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final color = accordRoleColor(role.color) ?? colors.dirtyWhite;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            role.name,
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: colors.dirtyWhite),
          ),
        ],
      ),
    );
  }
}

class _RoleEditor extends StatelessWidget {
  const _RoleEditor({
    required this.roles,
    required this.memberRoleIds,
    required this.enabled,
    required this.onToggle,
  });

  final List<AccordRole> roles;
  final List<String> memberRoleIds;
  final bool enabled;
  final void Function(AccordRole role, bool add) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          'ASSIGN ROLES',
          style: theme.textTheme.labelSmall!.copyWith(
            color: colors.gray,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final role in roles)
              FilterChip(
                label: Text(role.name),
                selected: memberRoleIds.contains(role.id),
                onSelected: enabled ? (value) => onToggle(role, value) : null,
                showCheckmark: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _ModerationActions extends StatelessWidget {
  const _ModerationActions({
    required this.canKick,
    required this.canBan,
    required this.canTimeout,
    required this.timedOut,
    required this.busy,
    required this.onKick,
    required this.onBan,
    required this.onTimeout,
    required this.onRemoveTimeout,
  });

  final bool canKick;
  final bool canBan;
  final bool canTimeout;
  final bool timedOut;
  final bool busy;
  final VoidCallback onKick;
  final VoidCallback onBan;
  final ValueChanged<int> onTimeout;
  final VoidCallback onRemoveTimeout;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canTimeout)
          PopupMenuButton<int>(
            enabled: !busy,
            tooltip: 'Time out',
            onSelected: onTimeout,
            itemBuilder: (context) => [
              for (final (label, seconds) in _timeoutDurations)
                PopupMenuItem(value: seconds, child: Text(label)),
            ],
            child: _ActionRow(
              icon: Icons.timer_outlined,
              label: 'Time out…',
              color: const Color(0xFFFAA81A),
            ),
          ),
        if (canTimeout && timedOut)
          _ActionTile(
            icon: Icons.timer_off_outlined,
            label: 'Remove timeout',
            color: colors.dirtyWhite,
            onTap: busy ? null : onRemoveTimeout,
          ),
        if (canKick)
          _ActionTile(
            icon: Icons.exit_to_app,
            label: 'Kick member',
            color: const Color(0xFFFAA81A),
            onTap: busy ? null : onKick,
          ),
        if (canBan)
          _ActionTile(
            icon: Icons.gavel,
            label: 'Ban member',
            color: colors.red,
            onTap: busy ? null : onBan,
          ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: _ActionRow(icon: icon, label: label, color: color),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// A centered dialog, or a raised card when the profile pops out beside a
/// click.
class _PopoutFrame extends StatelessWidget {
  const _PopoutFrame({
    required this.anchored,
    required this.color,
    required this.child,
  });

  final bool anchored;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    if (!anchored) {
      return Dialog(backgroundColor: color, shape: shape, child: child);
    }
    return Material(
      color: color,
      shape: shape,
      elevation: 12,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
