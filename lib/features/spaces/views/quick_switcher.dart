import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/shared/components/dialog_title_bar.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the quick switcher sends the user.
class QuickSwitchTarget {
  const QuickSwitchTarget({required this.spaceId, required this.channelId});
  final String spaceId;
  final String channelId;
}

/// One jumpable channel, with the space it lives in for the label.
class QuickSwitchEntry {
  const QuickSwitchEntry({
    required this.spaceId,
    required this.spaceName,
    required this.channel,
  });
  final String spaceId;
  final String spaceName;
  final AccordChannel channel;

  String get channelName => channel.name ?? channel.id;
}

/// The Ctrl+K dialog: type part of a channel or space name, ↑/↓ to move,
/// Enter to jump. Resolves to the pick, or null when dismissed.
Future<QuickSwitchTarget?> showQuickSwitcher(BuildContext context) {
  return showDialog<QuickSwitchTarget>(
    context: context,
    builder: (_) => const _QuickSwitcherDialog(),
  );
}

/// Up to [limit] entries matching [query]: prefix matches on the channel name
/// first, then substring matches on the channel or space name. An empty
/// query lists everything in rail order.
List<QuickSwitchEntry> filterQuickSwitchEntries(
  List<QuickSwitchEntry> entries,
  String query, {
  int limit = 12,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return entries.take(limit).toList();
  final prefix = <QuickSwitchEntry>[];
  final contains = <QuickSwitchEntry>[];
  for (final entry in entries) {
    final name = entry.channelName.toLowerCase();
    if (name.startsWith(q)) {
      prefix.add(entry);
    } else if (name.contains(q) ||
        entry.spaceName.toLowerCase().contains(q)) {
      contains.add(entry);
    }
  }
  return [...prefix, ...contains].take(limit).toList();
}

class _QuickSwitcherDialog extends ConsumerStatefulWidget {
  const _QuickSwitcherDialog();

  @override
  ConsumerState<_QuickSwitcherDialog> createState() =>
      _QuickSwitcherDialogState();
}

class _QuickSwitcherDialogState extends ConsumerState<_QuickSwitcherDialog> {
  final _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  String _query = '';
  int _highlighted = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<QuickSwitchEntry> _entries() {
    final activeKey = ref.read(connectionsControllerProvider).activeKey;
    final spaces = ref.watch(spacesControllerProvider);
    if (activeKey == null || spaces == null) return const [];
    return [
      for (final space in spaces)
        for (final channel
            in ref.watch(accordChannelsControllerProvider(activeKey, space.id)) ??
                const <AccordChannel>[])
          if (channel.type != 'category')
            QuickSwitchEntry(
              spaceId: space.id,
              spaceName: space.name,
              channel: channel,
            ),
    ];
  }

  List<QuickSwitchEntry> _matches = const [];

  void _pick(QuickSwitchEntry entry) {
    Navigator.of(context).pop(
      QuickSwitchTarget(spaceId: entry.spaceId, channelId: entry.channel.id),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      if (_matches.isEmpty) return KeyEventResult.handled;
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(
        () => _highlighted = (_highlighted + step) % _matches.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent && _matches.isNotEmpty) {
        _pick(_matches[_highlighted.clamp(0, _matches.length - 1)]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    _matches = filterQuickSwitchEntries(_entries(), _query);
    final highlighted = _matches.isEmpty
        ? 0
        : _highlighted.clamp(0, _matches.length - 1);
    return Dialog(
      backgroundColor: colors.background,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DialogTitleBar('Jump to…'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                key: const Key('quick-switcher-field'),
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Where would you like to go?',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() {
                  _query = value;
                  _highlighted = 0;
                }),
              ),
            ),
            Flexible(
              child: _matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No channel matches.',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.gray,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _matches.length,
                      itemBuilder: (context, index) {
                        final entry = _matches[index];
                        final selected = index == highlighted;
                        return ListTile(
                          key: Key('quick-switcher-${entry.channel.id}'),
                          dense: true,
                          selected: selected,
                          selectedTileColor: colors.foreground,
                          leading: Icon(
                            switch (entry.channel.type) {
                              'voice' => Icons.volume_up,
                              'stage' => Icons.podcasts,
                              'forum' => Icons.forum_outlined,
                              _ => Icons.tag,
                            },
                            size: 18,
                            color: colors.gray,
                          ),
                          title: Text(entry.channelName),
                          trailing: Text(
                            entry.spaceName,
                            style: theme.textTheme.labelSmall!.copyWith(
                              color: colors.gray,
                            ),
                          ),
                          onTap: () => _pick(entry),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                '↑ ↓ to move · Enter to jump · Esc to close',
                style: theme.textTheme.labelSmall!.copyWith(color: colors.gray),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
