part of '../accord_role_management.dart';

class _RoleListPane extends StatelessWidget {
  const _RoleListPane({
    required this.roles,
    required this.selectedId,
    required this.busy,
    required this.canEdit,
    required this.onSelect,
    required this.onCreate,
    required this.onReorder,
  });

  final List<AccordRole> roles;
  final String? selectedId;
  final bool busy;
  final bool Function(AccordRole) canEdit;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<List<AccordRole>> onReorder;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    // @everyone stays pinned at the bottom and isn't draggable.
    final draggable = roles.where((r) => r.position != 0).toList();
    final everyone = roles.firstWhereOrNull((r) => r.position == 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: FilledButton.icon(
            onPressed: busy ? null : onCreate,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Create role'),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) {
              if (busy) return;
              final reordered = [...draggable];
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              onReorder(reordered);
            },
            children: [
              for (var i = 0; i < draggable.length; i++)
                _RoleListTile(
                  key: ValueKey(draggable[i].id),
                  index: i,
                  role: draggable[i],
                  selected: draggable[i].id == selectedId,
                  draggable: canEdit(draggable[i]),
                  onTap: () => onSelect(draggable[i].id),
                ),
            ],
          ),
        ),
        if (everyone != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _RoleListTile(
              role: everyone,
              selected: everyone.id == selectedId,
              draggable: false,
              onTap: () => onSelect(everyone.id),
            ),
          ),
        if (everyone != null) Divider(height: 1, color: colors.background),
      ],
    );
  }
}

class _RoleListTile extends StatelessWidget {
  const _RoleListTile({
    super.key,
    required this.role,
    required this.selected,
    required this.draggable,
    required this.onTap,
    this.index,
  });

  final AccordRole role;
  final bool selected;
  final bool draggable;
  final VoidCallback onTap;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final dot = accordRoleColor(role.color) ?? colors.gray;
    final tile = Material(
      color: selected ? colors.darkGray : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  role.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (draggable && index != null)
                ReorderableDragStartListener(
                  index: index!,
                  child: Icon(Icons.drag_handle, size: 18, color: colors.gray),
                ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: tile,
    );
  }
}

class _RoleEditorPane extends StatefulWidget {
  const _RoleEditorPane({
    super.key,
    required this.role,
    required this.editable,
    required this.busy,
    required this.onSave,
    required this.onDelete,
    required this.onPreview,
  });

  final AccordRole role;
  final bool editable;
  final bool busy;
  final ValueChanged<AccordRole> onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onPreview;

  @override
  State<_RoleEditorPane> createState() => _RoleEditorPaneState();
}

class _RoleEditorPaneState extends State<_RoleEditorPane> {
  late TextEditingController _name;
  late int _color;
  late bool _hoist;
  late bool _mentionable;
  late Set<String> _permissions;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.role.name);
    _color = widget.role.color;
    _hoist = widget.role.hoist;
    _mentionable = widget.role.mentionable;
    _permissions = widget.role.permissions.map((p) => p.toString()).toSet();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final edited = AccordRole(
      id: widget.role.id,
      name: _name.text.trim().isEmpty ? widget.role.name : _name.text.trim(),
      color: _color,
      hoist: _hoist,
      icon: widget.role.icon,
      position: widget.role.position,
      permissions: _permissions.toList(),
      managed: widget.role.managed,
      mentionable: _mentionable,
    );
    widget.onSave(edited);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final enabled = widget.editable && !widget.busy;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.editable)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                widget.role.managed
                    ? 'This role is managed by an integration.'
                    : 'This role is at or above your highest role.',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
            ),
          Text(
            'ROLE NAME',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _name,
            enabled: enabled,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colors.darkGray,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'COLOR',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in _palette)
                _ColorSwatch(
                  value: value,
                  selected: value == _color,
                  onTap: enabled ? () => setState(() => _color = value) : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hoist,
            onChanged: enabled ? (v) => setState(() => _hoist = v) : null,
            title: const Text('Display separately'),
            subtitle: Text(
              'Show members with this role in their own section',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _mentionable,
            onChanged: enabled ? (v) => setState(() => _mentionable = v) : null,
            title: const Text('Allow @mention'),
            subtitle: Text(
              'Anyone can @mention this role',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'PERMISSIONS',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          for (final group in accordPermissionGroups) ...[
            const SizedBox(height: 10),
            Text(
              group.label.toUpperCase(),
              style: theme.textTheme.labelSmall!.copyWith(
                color: colors.gray,
                fontWeight: FontWeight.bold,
              ),
            ),
            for (final perm in group.permissions)
              _PermissionTile(
                perm: perm,
                value: _permissions.contains(perm),
                enabled: enabled,
                onChanged: (v) => setState(() {
                  if (v) {
                    _permissions.add(perm);
                  } else {
                    _permissions.remove(perm);
                  }
                }),
              ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (widget.onDelete != null)
                TextButton(
                  onPressed: enabled ? widget.onDelete : null,
                  style: TextButton.styleFrom(foregroundColor: colors.red),
                  child: const Text('Delete role'),
                ),
              if (widget.onPreview != null)
                TextButton.icon(
                  onPressed: widget.busy ? null : widget.onPreview,
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('Preview as role'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: enabled ? _save : null,
                child: const Text('Save changes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The role editor's 28px rounded-square variant of [ColorSwatchChip]; keeps
/// the role-value → color mapping (0 = "no color") local to this screen.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final int value;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final color = accordRoleColor(value);
    return ColorSwatchChip(
      color: color ?? colors.darkGray,
      selected: selected,
      onTap: onTap,
      size: 28,
      borderRadius: BorderRadius.circular(6),
      borderWidth: 2,
      icon: color == null ? Icons.format_color_reset : null,
      iconColor: color == null ? colors.gray : Colors.white,
      iconSize: 16,
      ink: true,
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.perm,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String perm;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  String get _label => accordPermissionLabel(perm);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final description = AccordPermission.description(perm);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: enabled ? (v) => onChanged(v) : null,
      title: Text(_label, style: theme.textTheme.bodyMedium),
      subtitle: description.isEmpty
          ? null
          : Text(
              description,
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
    );
  }
}
