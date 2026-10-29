import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/server_timestamp.dart';
import 'package:bonfire/shared/utils/ban_dialog.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/member/views/remote_origin_badge.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/member/views/profile_extras.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the pointer last went down, so the profile card can open beside
/// what was clicked (a name, an avatar, a member row) as in other chat apps.
Offset? _lastPointerDown;
DateTime? _lastPointerDownAt;
bool _trackingPointer = false;

/// Starts recording pointer-down positions for [showAccordMemberPopout].
/// Idempotent; the home screen calls it on mount.
void trackMemberPopoutAnchor() {
  if (_trackingPointer) return;
  _trackingPointer = true;
  GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
    if (event is PointerDownEvent) {
      _lastPointerDown = event.position;
      _lastPointerDownAt = DateTime.now();
    }
  });
}

/// Opens the member profile card for [userId] within [spaceId]. On desktop
/// it pops out beside the click that opened it; on touch layouts (or with no
/// recent click) it is a centered modal.
Future<void> showAccordMemberPopout(
  BuildContext context, {
  required String spaceId,
  required String userId,
}) {
  final at = _lastPointerDownAt;
  final anchor =
      shouldUseDesktopLayout(context) &&
          at != null &&
          DateTime.now().difference(at) < const Duration(seconds: 2)
      ? _lastPointerDown
      : null;
  if (anchor == null) {
    return showDialog<void>(
      context: context,
      builder: (_) => _MemberPopout(spaceId: spaceId, userId: userId),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close profile',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (_, _, _) => CustomSingleChildLayout(
      delegate: _PopoverLayout(anchor),
      child: _MemberPopout(spaceId: spaceId, userId: userId, anchored: true),
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Places the card to the right of [anchor] (to its left when there is no
/// room, e.g. clicks in the member list), its top near the click, kept on
/// screen.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(this.anchor);

  final Offset anchor;
  static const double _margin = 12;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(360, (constraints.maxHeight - 2 * _margin).clamp(0, 900)),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.dx + 16;
    if (x + childSize.width > size.width - _margin) {
      x = anchor.dx - 16 - childSize.width;
    }
    final y = (anchor.dy - 40).clamp(
      _margin,
      (size.height - childSize.height - _margin).clamp(_margin, size.height),
    );
    return Offset(
      x.clamp(_margin, (size.width - childSize.width - _margin).clamp(_margin, size.width)),
      y.toDouble(),
    );
  }

  @override
  bool shouldRelayout(_PopoverLayout oldDelegate) => anchor != oldDelegate.anchor;
}

/// Available timeout durations (label → seconds), mirroring the reference
/// client's `moderate_member_dialog`.
const _timeoutDurations = <(String, int)>[
  ('60 seconds', 60),
  ('5 minutes', 300),
  ('10 minutes', 600),
  ('1 hour', 3600),
  ('1 day', 86400),
  ('1 week', 604800),
];

class _MemberPopout extends ConsumerStatefulWidget {
  const _MemberPopout({
    required this.spaceId,
    required this.userId,
    this.anchored = false,
  });

  final String spaceId;
  final String userId;

  /// Shown beside a click (a plain card) rather than as a centered dialog.
  final bool anchored;

  @override
  ConsumerState<_MemberPopout> createState() => _MemberPopoutState();
}

class _MemberPopoutState extends ConsumerState<_MemberPopout> {
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.accordClient;
  String get _serverKey => ref.readActiveServerKey() ?? '';

  Future<void> _run(
    Future<RestResult> Function(AccordClient client) action, {
    String failure = 'Action failed',
    bool closeOnSuccess = false,
    VoidCallback? onSuccess,

    /// Given the successful result, for actions that report something back
    /// (e.g. how many messages a ban purged). Runs before [closeOnSuccess]
    /// pops, so it must not touch this popout's context.
    void Function(RestResult result)? onResult,
    bool missingIsSuccess = false,
  }) async {
    final client = _client;
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action(client);
    if (!mounted) return;
    // For removal actions (kick/ban), a "resource does not exist" / not-found
    // error means the member is already gone server-side — the desired end
    // state. Treat it as success so a stale roster row still gets cleared
    // instead of leaving the member stuck with a confusing error.
    final ok = result.ok || (missingIsSuccess && _isMissingResource(result));
    if (ok) {
      onSuccess?.call();
      onResult?.call(result);
      if (closeOnSuccess) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _busy = false);
    } else {
      setState(() {
        _busy = false;
        _error = result.errorOr(failure);
      });
    }
  }

  /// Whether [result] is a "the target no longer exists" error (HTTP 404 or the
  /// server's foreign-key / not-found message), meaning the member is already
  /// absent.
  bool _isMissingResource(RestResult result) {
    if (result.statusCode == 404) return true;
    final msg = result.error?.toString().toLowerCase() ?? '';
    return msg.contains('does not exist') || msg.contains('not found');
  }

  void _kick() {
    _run(
      (c) => c.members.kick(widget.spaceId, widget.userId),
      failure: 'Failed to kick member',
      closeOnSuccess: true,
      missingIsSuccess: true,
      onSuccess: () => ref
          .read(
            accordMembersControllerProvider(
              _serverKey,
              widget.spaceId,
            ).notifier,
          )
          .removeMember(widget.userId),
    );
  }

  /// Reports this user to the space's moderators, with the option to block
  /// them at the same time (App Review 1.2 — see #290).
  void _report() {
    showReportDialog(
      context,
      spaceId: widget.spaceId,
      targetType: 'user',
      targetId: widget.userId,
      reportedUserId: widget.userId,
      reportedName: _displayName,
    );
  }

  /// Blocks this user (relationship type 2). Account-level, not space-scoped —
  /// uses `users.putRelationship`. Unblocking lives in the Friends → Blocked
  /// list.
  Future<void> _block() async {
    final confirmed = await _confirm(
      title: 'Block user',
      message:
          'Blocked users can\'t message you directly or notify you. Their '
          'messages in spaces stay visible. Continue?',
      action: 'Block',
    );
    if (confirmed != true) return;
    _run(
      (c) => c.users.putRelationship(widget.userId, {
        'type': accordBlockedRelationship,
      }),
      failure: 'Failed to block user',
      closeOnSuccess: true,
      // Applies the block (DMs hidden, notifications silenced) right away
      // rather than at the next relationship fetch (#290).
      onSuccess: () => ref.blockedUsers.block(widget.userId),
    );
  }

  /// The member's display name, resolved the same way [build] resolves it, for
  /// the moderation dialogs that name their target.
  String get _displayName {
    final member = ref.read(
      accordMembersControllerProvider(_serverKey, widget.spaceId),
    )?[widget.userId];
    if (member != null) return accordMemberName(member);
    final cached = ref.read(
      accordUsersControllerProvider(_serverKey),
    )[widget.userId];
    return accordUserName(cached, fallback: widget.userId);
  }

  Future<void> _ban() async {
    // Resolved up front because the ban removes the member from the roster
    // cache `_displayName` reads, leaving only the raw id afterwards.
    final name = _displayName;
    final request = await showBanDialog(context, memberName: name);
    if (request == null || !mounted) return;
    // Captured now: the popout pops itself on success, so by the time the
    // result lands its own context can no longer find a messenger.
    final messenger = ScaffoldMessenger.maybeOf(context);
    _run(
      (c) =>
          c.bans.create(widget.spaceId, widget.userId, data: request.toJson()),
      failure: 'Failed to ban member',
      closeOnSuccess: true,
      missingIsSuccess: true,
      onSuccess: () => ref
          .read(
            accordMembersControllerProvider(
              _serverKey,
              widget.spaceId,
            ).notifier,
          )
          .removeMember(widget.userId),
      onResult: (result) {
        if (request.deleteMessageSeconds == 0) return;
        // Reported rather than assumed: a server that predates the purge
        // ignores the field, and this is the only way that shows up.
        final count = _deletedMessageCount(result);
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              count == 1
                  ? 'Banned $name and deleted 1 message'
                  : 'Banned $name and deleted $count messages',
            ),
          ),
        );
      },
    );
  }

  /// `deleted_message_count` from a ban response, or 0 when the server didn't
  /// report one (i.e. it doesn't support purging on ban).
  int _deletedMessageCount(RestResult result) {
    final data = result.data;
    if (data is! Map) return 0;
    final count = data['deleted_message_count'];
    return asInt(count);
  }

  void _timeout(int seconds) {
    final until = DateTime.now().toUtc().add(Duration(seconds: seconds));
    final iso = '${until.toIso8601String().split('.').first}Z';
    _run(
      (c) => c.members.update(widget.spaceId, widget.userId, {
        'communication_disabled_until': iso,
      }),
      failure: 'Failed to time out member',
    );
  }

  void _removeTimeout() {
    _run(
      (c) => c.members.update(widget.spaceId, widget.userId, {
        'communication_disabled_until': null,
      }),
      failure: 'Failed to remove timeout',
    );
  }

  /// Sets or clears [member]'s nickname. An empty value resets to the display
  /// name. Optimistically mirrors the result into the member cache.
  Future<void> _editNickname(AccordMember member) async {
    final initial = member.nickname ?? '';
    final next = (await showTextPromptDialog(
      context,
      title: 'Change nickname',
      label: 'Nickname',
      hintText: 'Leave empty to reset to their display name',
      initial: initial,
      resetLabel: initial.isNotEmpty ? 'Reset' : null,
    ))?.trim();
    if (next == null || !mounted) return;
    _run(
      (c) => c.members.update(widget.spaceId, widget.userId, {
        'nickname': next.isEmpty ? null : next,
      }),
      failure: 'Failed to update nickname',
      onSuccess: () {
        member.nickname = next.isEmpty ? null : next;
        ref
            .read(
              accordMembersControllerProvider(
                _serverKey,
                widget.spaceId,
              ).notifier,
            )
            .upsertMember(member);
      },
    );
  }

  void _toggleRole(AccordMember member, AccordRole role, bool add) {
    _run(
      (c) => add
          ? c.members.addRole(widget.spaceId, widget.userId, role.id)
          : c.members.removeRole(widget.spaceId, widget.userId, role.id),
      failure: 'Failed to update roles',
      onSuccess: () {
        final roles = [...member.roles];
        if (add) {
          if (!roles.contains(role.id)) roles.add(role.id);
        } else {
          roles.remove(role.id);
        }
        member.roles = roles;
        ref
            .read(
              accordMembersControllerProvider(
                _serverKey,
                widget.spaceId,
              ).notifier,
            )
            .upsertMember(member);
      },
    );
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String action,
  }) {
    return showConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: action,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);

    final members = ref.watch(
      accordMembersControllerProvider(_serverKey, widget.spaceId),
    );
    final member = members?[widget.userId];
    // Backfill the target from the on-demand user cache when outside the page.
    final cachedUser = ref.watch(
      accordUsersControllerProvider(_serverKey).select((m) => m[widget.userId]),
    );
    if (member == null && cachedUser == null && members != null) {
      ref
          .read(accordUsersControllerProvider(_serverKey).notifier)
          .ensure(widget.userId);
    }

    final space = ref.watch(
      spacesControllerProvider.select(
        (s) => s?.firstWhereOrNull((sp) => sp.id == widget.spaceId),
      ),
    );
    final roles = space?.roles ?? const <AccordRole>[];
    final status = ref.watch(
      activePresencesProvider.select(
        (p) => accordPresenceStatus(p, widget.userId),
      ),
    );
    final customStatus = ref.watch(
      activePresencesProvider.select(
        (p) => accordCustomStatus(p, widget.userId),
      ),
    );
    final cdnUrl = ref.watchCdnUrl();
    final currentUserId = ref.watchUserId();

    final name = member != null
        ? accordMemberName(member)
        : accordUserName(cachedUser, fallback: widget.userId);
    final username = member?.user?.username ?? cachedUser?.username;
    final avatarUrl = member != null
        ? accordMemberAvatarUrl(member, cdnUrl)
        : accordAvatarUrl(cachedUser, cdnUrl);
    final colorRole = member == null ? null : memberColorRole(member, roles);
    final nameColor = colorRole == null
        ? null
        : accordRoleColor(colorRole.color);

    final perms = ref.watchAccordPermissions(space, widget.spaceId);
    final isSelf = currentUserId != null && currentUserId == widget.userId;
    // A remote (federated) user is homed on another server; local-only
    // moderation (kick/ban/timeout/roles/nickname) can't be performed on them
    // here, so those actions are suppressed regardless of local permissions.
    final remoteDomain =
        accordMemberOrigin(member) ?? accordUserOrigin(cachedUser);
    final isRemote = remoteDomain != null;
    final canKick =
        !isSelf &&
        !isRemote &&
        accordHasPermission(perms, AccordPermission.kickMembers);
    final canBan =
        !isSelf &&
        !isRemote &&
        accordHasPermission(perms, AccordPermission.banMembers);
    final canTimeout =
        !isSelf &&
        !isRemote &&
        accordHasPermission(perms, AccordPermission.moderateMembers);
    final canManageRoles =
        !isRemote && accordHasPermission(perms, AccordPermission.manageRoles);
    final canEditNickname =
        !isRemote &&
        (isSelf
            ? accordHasPermission(perms, AccordPermission.changeNickname)
            : accordHasPermission(perms, AccordPermission.manageNicknames));
    final timedOut =
        member?.timedOutUntil != null &&
        member!.timedOutUntil.toString().isNotEmpty;

    // Roles assignable in the popout: skip @everyone (position 0) and managed.
    final assignableRoles = roles
        .where((r) => r.position != 0 && !r.managed)
        .sortedBy<num>((r) => -r.position);
    final memberRoleIds = member?.roles ?? const <String>[];

    return _PopoutFrame(
      anchored: widget.anchored,
      color: colors.foreground,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileThemeBand(serverKey: _serverKey, userId: widget.userId),
              _ProfileHeader(
                name: name,
                username: username,
                avatarUrl: avatarUrl,
                avatarBackgroundColor: accordAvatarColor(
                  member?.user,
                  widget.userId,
                ),
                status: status,
                nameColor: nameColor,
                customStatus: customStatus,
                remoteDomain: remoteDomain,
              ),
              ProfileExtrasSection(
                serverKey: _serverKey,
                userId: widget.userId,
                isSelf: isSelf,
                bio: member?.user?.bio ?? cachedUser?.bio,
              ),
              if (timedOut) ...[
                const SizedBox(height: 12),
                _TimeoutBanner(
                  label: 'Timed out until ${member.timedOutUntil}',
                ),
              ],
              if (member != null)
                _MembershipInfo(
                  member: member,
                  roles: roles,
                  memberRoleIds: memberRoleIds,
                ),
              if (canManageRoles &&
                  member != null &&
                  assignableRoles.isNotEmpty)
                _RoleEditor(
                  roles: assignableRoles,
                  memberRoleIds: memberRoleIds,
                  enabled: !_busy,
                  onToggle: (role, add) => _toggleRole(member, role, add),
                ),
              if (canEditNickname && member != null) ...[
                const SizedBox(height: 8),
                _ActionTile(
                  icon: Icons.badge_outlined,
                  label: (member.nickname ?? '').isEmpty
                      ? 'Set nickname'
                      : 'Edit nickname',
                  color: colors.dirtyWhite,
                  onTap: _busy ? null : () => _editNickname(member),
                ),
              ],
              if (canKick || canBan || canTimeout) ...[
                const SizedBox(height: 16),
                Divider(color: colors.background, height: 1),
                const SizedBox(height: 12),
                _ModerationActions(
                  canKick: canKick,
                  canBan: canBan,
                  canTimeout: canTimeout,
                  timedOut: timedOut,
                  busy: _busy,
                  onKick: _kick,
                  onBan: _ban,
                  onTimeout: _timeout,
                  onRemoveTimeout: _removeTimeout,
                ),
              ],
              if (!isSelf) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => openAccordDirectMessage(
                            context,
                            ref,
                            widget.userId,
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                    ),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Direct Message'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FriendActionButton(
                    user:
                        member?.user ??
                        cachedUser ??
                        AccordUser(id: widget.userId),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _report,
                    style: TextButton.styleFrom(foregroundColor: colors.red),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Report user'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _block,
                    style: TextButton.styleFrom(foregroundColor: colors.red),
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Block user'),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                InlineError(_error!, centered: false),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
