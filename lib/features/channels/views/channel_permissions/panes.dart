part of '../channel_permissions.dart';

class _Footer extends StatelessWidget {
  const _Footer({
    required this.colors,
    required this.saving,
    required this.canReset,
    required this.onReset,
    required this.onSave,
  });

  final BonfireThemeExtension colors;
  final bool saving;
  final bool canReset;
  final VoidCallback onReset;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.background, width: 1)),
      ),
      // OverflowBar wraps Reset/Save onto two lines when large text scale
      // makes them too wide for a phone, instead of overflowing.
      child: OverflowBar(
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        spacing: 8,
        overflowSpacing: 8,
        children: [
          TextButton(
            onPressed: (saving || !canReset) ? null : onReset,
            child: const Text('Reset'),
          ),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: Text(saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _EntityListPane extends StatelessWidget {
  const _EntityListPane({
    required this.compact,
    required this.roles,
    required this.memberIds,
    required this.selectedId,
    required this.roleColor,
    required this.memberName,
    required this.onSelectRole,
    required this.onSelectMember,
    required this.onAddMember,
  });

  /// Horizontal chip strip (narrow screens) instead of a vertical list.
  final bool compact;
  final List<AccordRole> roles;
  final List<String> memberIds;
  final String? selectedId;
  final Color? Function(String) roleColor;
  final String Function(String) memberName;
  final ValueChanged<String> onSelectRole;
  final ValueChanged<String> onSelectMember;
  final VoidCallback onAddMember;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final children = [
      for (final role in roles)
        _EntityRow(
          key: ValueKey('role-${role.id}'),
          compact: compact,
          label: role.name,
          color: roleColor(role.id) ?? colors.dirtyWhite,
          icon: Icons.shield_outlined,
          selected: role.id == selectedId,
          onTap: () => onSelectRole(role.id),
        ),
      if (compact)
        // The strip has no room for a section header; a thin rule separates
        // roles from members (the chip icons already tell them apart).
        Container(
          width: 1,
          height: 24,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: colors.darkGray,
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
          child: Text(
            'MEMBERS',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              letterSpacing: 0.6,
            ),
          ),
        ),
      for (final id in memberIds)
        _EntityRow(
          key: ValueKey('member-$id'),
          compact: compact,
          label: memberName(id),
          color: colors.dirtyWhite,
          icon: Icons.person_outline,
          selected: id == selectedId,
          onTap: () => onSelectMember(id),
        ),
      _EntityRow(
        key: const ValueKey('add-member'),
        compact: compact,
        label: '+ Add Member',
        color: colors.primary,
        icon: Icons.add,
        selected: false,
        onTap: onAddMember,
      ),
    ];
    if (compact) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              children[i],
            ],
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      children: children,
    );
  }
}

class _EntityRow extends StatefulWidget {
  const _EntityRow({
    super.key,
    this.compact = false,
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  /// Renders as a self-sized chip (for the horizontal strip) instead of a
  /// full-width list row.
  final bool compact;
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_EntityRow> createState() => _EntityRowState();
}

class _EntityRowState extends State<_EntityRow> {
  @override
  void initState() {
    super.initState();
    if (widget.selected) _reveal();
  }

  @override
  void didUpdateWidget(_EntityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) _reveal();
  }

  /// Scrolls this row into view once it becomes the selection — matters for
  /// the compact strip, where "+ Add Member" appends the new chip off-screen.
  /// Only on selection change, so it never fights the user's own scrolling.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 150),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final compact = widget.compact;
    final selected = widget.selected;
    final color = widget.color;
    final radius = BorderRadius.circular(compact ? 20 : 8);
    final text = Text(
      widget.label,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium!.copyWith(color: color),
    );
    return Material(
      color: selected ? colors.darkGray : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        // Unselected chips need an outline to read as tappable in the strip.
        side: compact
            ? BorderSide(color: selected ? color : colors.darkGray)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: widget.onTap,
        child: Padding(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(widget.icon, size: 16, color: color),
              SizedBox(width: compact ? 8 : 10),
              if (compact)
                // Long role names must not stretch the strip; cap the chip.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: text,
                )
              else
                Expanded(child: text),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverwriteEditorPane extends StatelessWidget {
  const _OverwriteEditorPane({
    super.key,
    required this.data,
    required this.visiblePerms,
    required this.enabled,
    this.compact = false,
    required this.onSet,
  });

  final Map<String, _OverwriteState> data;
  final Set<String> visiblePerms;
  final bool enabled;

  /// Tighter margins and finger-sized tri-state buttons (narrow screens).
  final bool compact;
  final void Function(String perm, _OverwriteState state) onSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return SingleChildScrollView(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 8, 12, 16)
          : const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in accordPermissionGroups)
            ..._buildGroup(context, theme, colors, group),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(
    BuildContext context,
    ThemeData theme,
    BonfireThemeExtension colors,
    ({String label, List<String> permissions}) group,
  ) {
    final perms = group.permissions.where(visiblePerms.contains).toList();
    if (perms.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          group.label.toUpperCase(),
          style: theme.textTheme.labelSmall!.copyWith(
            color: colors.gray,
            letterSpacing: 0.6,
          ),
        ),
      ),
      for (final perm in perms)
        _PermissionRow(
          label: accordPermissionLabel(perm),
          description: AccordPermission.description(perm),
          state: data[perm] ?? _OverwriteState.neutral,
          enabled: enabled,
          compact: compact,
          onChanged: (s) => onSet(perm, s),
        ),
    ];
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.label,
    required this.description,
    required this.state,
    required this.enabled,
    this.compact = false,
    required this.onChanged,
  });

  final String label;
  final String description;
  final _OverwriteState state;
  final bool enabled;

  /// Finger-sized (40px) tri-state buttons for touch screens.
  final bool compact;
  final ValueChanged<_OverwriteState> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final gap = SizedBox(width: compact ? 6 : 4);
    // The label wraps freely while the three buttons keep their fixed size;
    // the pane is full-width on phones so the text is never squeezed into a
    // letter-per-line column (#328).
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 6 : 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          SizedBox(width: compact ? 12 : 8),
          _TriButton(
            icon: Icons.check,
            color: colors.green,
            compact: compact,
            selected: state == _OverwriteState.allow,
            onTap: enabled
                ? () => onChanged(
                    state == _OverwriteState.allow
                        ? _OverwriteState.neutral
                        : _OverwriteState.allow,
                  )
                : null,
          ),
          gap,
          _TriButton(
            icon: Icons.remove,
            color: colors.gray,
            compact: compact,
            selected: state == _OverwriteState.neutral,
            onTap: enabled ? () => onChanged(_OverwriteState.neutral) : null,
          ),
          gap,
          _TriButton(
            icon: Icons.close,
            color: colors.red,
            compact: compact,
            selected: state == _OverwriteState.deny,
            onTap: enabled
                ? () => onChanged(
                    state == _OverwriteState.deny
                        ? _OverwriteState.neutral
                        : _OverwriteState.deny,
                  )
                : null,
          ),
        ],
      ),
    );
    return description.isEmpty
        ? row
        : Tooltip(message: description, child: row);
  }
}

class _TriButton extends StatelessWidget {
  const _TriButton({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  /// 40px touch target instead of the 30x28 desktop button.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: compact ? 40 : 30,
        height: compact ? 40 : 28,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? color : colors.darkGray,
            width: 1.5,
          ),
        ),
        child: Icon(icon, size: 16, color: selected ? color : colors.gray),
      ),
    );
  }
}
