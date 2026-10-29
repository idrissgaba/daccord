import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/components/color_swatch_chip.dart';
import 'package:bonfire/shared/components/dialog_title_bar.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/utils/permission_catalog.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/role_preview.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'role_management/panes.dart';

/// Opens the role management dialog for [spaceId]: list, create, edit, delete,
/// and reorder roles, with a permission grid. The Accord analogue of the
/// reference client's `role_management_dialog`. Hierarchy is enforced — a user
/// may only act on roles strictly below their own highest role.
Future<void> showAccordRoleManagement(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RoleManagement(spaceId: spaceId),
  );
}

/// A small preset palette for the color picker, matching the reference client's
/// common role colors. The leading entry (0) means "no color".
const _palette = <int>[
  0x000000,
  0x1ABC9C,
  0x2ECC71,
  0x3498DB,
  0x9B59B6,
  0xE91E63,
  0xF1C40F,
  0xE67E22,
  0xE74C3C,
  0x95A5A6,
  0x607D8B,
  0x11806A,
  0x1F8B4C,
  0x206694,
  0x71368A,
  0xAD1457,
  0xC27C0E,
  0xA84300,
  0x992D22,
];

class _RoleManagement extends ConsumerStatefulWidget {
  const _RoleManagement({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_RoleManagement> createState() => _RoleManagementState();
}

class _RoleManagementState extends ConsumerState<_RoleManagement> {
  String? _selectedRoleId;
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.accordClient;

  List<AccordRole> get _roles {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    return space?.roles ?? const <AccordRole>[];
  }

  int _myHighest() {
    final space = ref
        .read(spacesControllerProvider)
        ?.firstWhereOrNull((s) => s.id == widget.spaceId);
    final currentUserId = ref.readUserId();
    final isAdmin = ref.readIsAdmin();
    final members = ref.read(
      accordMembersControllerProvider(
        ref.readActiveServerKey() ?? '',
        widget.spaceId,
      ),
    );
    return accordMyHighestRolePosition(
      space: space,
      selfMember: currentUserId == null ? null : members?[currentUserId],
      roles: _roles,
      currentUserId: currentUserId ?? '',
      currentUserIsAdmin: isAdmin,
    );
  }

  /// A role is editable when it sits strictly below the user's highest role and
  /// isn't integration-managed. `@everyone` (position 0) is editable for its
  /// permissions but can't be deleted or reordered.
  bool _canEdit(AccordRole role) =>
      !role.managed && role.position < _myHighest();

  Future<T?> _run<T>(
    Future<RestResult> Function(AccordClient client) action, {
    String failure = 'Action failed',
  }) async {
    final client = _client;
    if (client == null || _busy) return null;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action(client);
    if (!mounted) return null;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.errorOr(failure);
    });
    return result.ok ? result.data as T? : null;
  }

  Future<void> _createRole() async {
    final role = await _run<AccordRole>(
      (c) => c.roles.create(widget.spaceId, {
        'name': 'new role',
        'color': 0,
        'hoist': false,
        'mentionable': false,
        'permissions': <String>[],
      }),
      failure: 'Failed to create role',
    );
    if (role == null || !mounted) return;
    ref
        .read(spacesControllerProvider.notifier)
        .upsertRole(widget.spaceId, role);
    setState(() => _selectedRoleId = role.id);
  }

  Future<void> _saveRole(AccordRole edited) async {
    final role = await _run<AccordRole>(
      (c) => c.roles.update(widget.spaceId, edited.id, {
        'name': edited.name,
        'color': edited.color,
        'hoist': edited.hoist,
        'mentionable': edited.mentionable,
        'permissions': edited.permissions,
      }),
      failure: 'Failed to save role',
    );
    if (role == null || !mounted) return;
    ref
        .read(spacesControllerProvider.notifier)
        .upsertRole(widget.spaceId, role);
  }

  /// Enters "preview as role" for [role] and closes this dialog so the user
  /// sees the app gated as that role would (with the exit banner up top).
  void _previewRole(AccordRole role) {
    ref
        .read(rolePreviewControllerProvider.notifier)
        .enter(
          RolePreview(
            spaceId: widget.spaceId,
            roleId: role.id,
            roleName: role.name,
          ),
        );
    Navigator.of(context).maybePop();
  }

  Future<void> _deleteRole(AccordRole role) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete role',
      message: 'Delete the "${role.name}" role? This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (confirmed != true) return;
    final ok = await _run(
      (c) => c.roles.delete(widget.spaceId, role.id),
      failure: 'Failed to delete role',
    );
    if (ok == null && _error != null) return;
    if (!mounted) return;
    ref
        .read(spacesControllerProvider.notifier)
        .removeRole(widget.spaceId, role.id);
    setState(() {
      if (_selectedRoleId == role.id) _selectedRoleId = null;
    });
  }

  /// Reorders the editable (non-@everyone) roles after a drag, then persists the
  /// new positions. Positions count down from the top so higher roles outrank.
  Future<void> _reorder(List<AccordRole> ordered) async {
    // Assign descending positions, keeping @everyone pinned at 0.
    final payload = <Map<String, dynamic>>[];
    var position = ordered.length;
    for (final role in ordered) {
      payload.add({'id': role.id, 'position': position});
      position--;
    }
    final updated = await _run<List<dynamic>>(
      (c) => c.roles.reorder(widget.spaceId, payload),
      failure: 'Failed to reorder roles',
    );
    if (!mounted) return;
    if (updated != null) {
      final roles = updated.whereType<AccordRole>().toList();
      if (roles.isNotEmpty) {
        ref
            .read(spacesControllerProvider.notifier)
            .setRoles(widget.spaceId, roles);
        return;
      }
    }
    // Fall back to optimistic local reorder if the server returns nothing.
    for (final entry in payload) {
      final role = _roles.firstWhereOrNull((r) => r.id == entry['id']);
      if (role != null) role.position = entry['position'] as int;
    }
    ref.read(spacesControllerProvider.notifier).setRoles(widget.spaceId, [
      ..._roles,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final roles = ref.watch(
      spacesControllerProvider.select(
        (spaces) =>
            spaces?.firstWhereOrNull((s) => s.id == widget.spaceId)?.roles ??
            const <AccordRole>[],
      ),
    );
    final sorted = [...roles]..sort((a, b) => b.position.compareTo(a.position));
    final selected = sorted.firstWhereOrNull((r) => r.id == _selectedRoleId);

    return Dialog(
      backgroundColor: colors.foreground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 720, maxHeight: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.background, width: 1),
                ),
              ),
              child: const DialogTitleBar('Roles'),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 240,
                    child: _RoleListPane(
                      roles: sorted,
                      selectedId: _selectedRoleId,
                      busy: _busy,
                      canEdit: _canEdit,
                      onSelect: (id) => setState(() => _selectedRoleId = id),
                      onCreate: _createRole,
                      onReorder: _reorder,
                    ),
                  ),
                  VerticalDivider(width: 1, color: colors.background),
                  Expanded(
                    child: selected == null
                        ? Center(
                            child: Text(
                              'Select a role to edit',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : _RoleEditorPane(
                            key: ValueKey(selected.id),
                            role: selected,
                            editable: _canEdit(selected),
                            busy: _busy,
                            onSave: _saveRole,
                            onDelete: selected.position == 0
                                ? null
                                : () => _deleteRole(selected),
                            onPreview: () => _previewRole(selected),
                          ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: InlineError(_error!, centered: false),
              ),
          ],
        ),
      ),
    );
  }
}
