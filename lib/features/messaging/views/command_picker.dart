import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/app_commands.dart';
import 'package:bonfire/features/messaging/utils/interaction_logic.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The slash commands matching what's typed after `/`, above the message
/// box. Hidden when nothing matches.
class CommandPopup extends ConsumerWidget {
  const CommandPopup({
    super.key,
    required this.serverKey,
    required this.spaceId,
    required this.query,
    required this.onPick,
  });

  final String serverKey;
  final String spaceId;
  final String query;
  final ValueChanged<AccordCommand> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final commands = ref.watch(
      spaceCommandsControllerProvider(serverKey, spaceId),
    );
    final matches = matchCommands(commands ?? const [], query);
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const Key('command-popup'),
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.foreground, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final command in matches)
            InkWell(
              key: ValueKey('command-${command.name}'),
              onTap: () => onPick(command),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(Icons.terminal, size: 14, color: colors.gray),
                    const SizedBox(width: 8),
                    Text('/${command.name}', style: theme.textTheme.titleSmall),
                    for (final option in command.options.where(
                      (o) => o.required,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          option.name,
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: colors.gray,
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        command.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: colors.gray,
                        ),
                      ),
                    ),
                    if (command.applicationName.isNotEmpty)
                      Text(
                        command.applicationName,
                        style: theme.textTheme.labelSmall!.copyWith(
                          color: colors.gray,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The options of a picked slash command, filled in before running it:
/// a text field per text or number option, a list for fixed choices, a
/// switch for yes/no, and member / channel / role pickers.
class CommandForm extends ConsumerStatefulWidget {
  const CommandForm({
    super.key,
    required this.serverKey,
    required this.spaceId,
    required this.command,
    required this.onRun,
    required this.onCancel,
  });

  final String serverKey;
  final String spaceId;
  final AccordCommand command;

  /// Runs the command with `{name, value}` options; resolves to the reason it
  /// failed, or null.
  final Future<String?> Function(List<Map<String, dynamic>> options) onRun;
  final VoidCallback onCancel;

  @override
  ConsumerState<CommandForm> createState() => _CommandFormState();
}

class _CommandFormState extends ConsumerState<CommandForm> {
  final _text = <String, TextEditingController>{};
  final _picks = <String, Object?>{};
  String? _error;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    for (final option in widget.command.options) {
      if (_isTyped(option)) _text[option.name] = TextEditingController();
      if (option.type == 'boolean') _picks[option.name] = false;
    }
  }

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _isTyped(AccordCommandOption option) =>
      option.choices.isEmpty &&
      const {'string', 'integer', 'number'}.contains(option.type);

  Future<void> _run() async {
    if (_running) return;
    final raw = <String, Object?>{
      for (final entry in _text.entries) entry.key: entry.value.text,
      ..._picks,
    };
    final collected = collectOptions(widget.command, raw);
    if (collected.error != null) {
      setState(() => _error = collected.error);
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    final error = await widget.onRun(collected.options);
    if (!mounted) return;
    setState(() {
      _running = false;
      _error = error;
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _field(AccordCommandOption option) {
    final label = option.required ? option.name : '${option.name} (optional)';
    if (_isTyped(option)) {
      final numeric = option.type != 'string';
      return SizedBox(
        width: option.type == 'string' ? 260 : 120,
        child: TextField(
          key: ValueKey('command-option-${option.name}'),
          controller: _text[option.name],
          autofocus: option == widget.command.options.first,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                )
              : TextInputType.text,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            isDense: true,
            labelText: label,
            helperText: option.description,
            helperMaxLines: 1,
          ),
        ),
      );
    }
    if (option.type == 'boolean') {
      return FilterChip(
        key: ValueKey('command-option-${option.name}'),
        label: Text(option.name),
        tooltip: option.description,
        selected: _picks[option.name] == true,
        onSelected: (value) => setState(() => _picks[option.name] = value),
      );
    }
    final items = _choicesFor(option);
    return DropdownButton<Object?>(
      key: ValueKey('command-option-${option.name}'),
      hint: Text(label),
      value: items.any((i) => i.value == _picks[option.name])
          ? _picks[option.name]
          : null,
      onChanged: (value) => setState(() => _picks[option.name] = value),
      items: [
        if (!option.required)
          const DropdownMenuItem<Object?>(value: null, child: Text('—')),
        ...items,
      ],
    );
  }

  List<DropdownMenuItem<Object?>> _choicesFor(AccordCommandOption option) {
    if (option.choices.isNotEmpty) {
      return [
        for (final choice in option.choices)
          DropdownMenuItem<Object?>(
            value: choice.value,
            child: Text(choice.name),
          ),
      ];
    }
    switch (option.type) {
      case 'user':
        final members =
            ref.watch(
              accordMembersControllerProvider(widget.serverKey, widget.spaceId),
            ) ??
            const <String, AccordMember>{};
        return [
          for (final member in members.values)
            DropdownMenuItem<Object?>(
              value: member.userId,
              child: Text(accordMemberName(member)),
            ),
        ];
      case 'channel':
        final channels =
            ref.watch(
              accordChannelsControllerProvider(
                widget.serverKey,
                widget.spaceId,
              ),
            ) ??
            const <AccordChannel>[];
        return [
          for (final channel in channels.where((c) => c.type != 'category'))
            DropdownMenuItem<Object?>(
              value: channel.id,
              child: Text('#${channel.name ?? channel.id}'),
            ),
        ];
      case 'role':
        final roles =
            ref.watch(
              spacesControllerProvider.select(
                (spaces) => spaces
                    ?.firstWhereOrNull((s) => s.id == widget.spaceId)
                    ?.roles,
              ),
            ) ??
            const <AccordRole>[];
        return [
          for (final role in roles)
            DropdownMenuItem<Object?>(value: role.id, child: Text(role.name)),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final command = widget.command;
    return Focus(
      onKeyEvent: _onKey,
      child: Padding(
        key: const Key('command-form'),
        padding: const EdgeInsets.fromLTRB(8, 6, 4, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Chip(
                    avatar: const Icon(Icons.terminal, size: 14),
                    label: Text('/${command.name}'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final option in command.options) _field(option),
                      if (command.options.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            command.description,
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: colors.gray,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('command-cancel'),
                  tooltip: 'Cancel (Esc)',
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close, size: 18),
                ),
                IconButton(
                  key: const Key('command-run'),
                  tooltip: 'Run /${command.name}',
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.send, size: 20, color: colors.dirtyWhite),
                ),
              ],
            ),
            if (_error != null)
              Text(
                _error!,
                style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
              ),
          ],
        ),
      ),
    );
  }
}

/// Under the message box: "Sending /play…" while a command waits for its
/// bot, then "The application did not respond." if it never answers.
class InteractionStatusLine extends ConsumerWidget {
  const InteractionStatusLine({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(
      interactionTrackerProvider.select(
        (all) => all.values
            .where((p) => p.channelId == channelId && p.commandName != null)
            .toList(),
      ),
    );
    if (pending.isEmpty) return const SizedBox.shrink();
    final latest = pending.last;
    final colors = BonfireThemeExtension.of(context);
    final style = Theme.of(context).textTheme.bodySmall!;
    return Padding(
      key: const Key('interaction-status'),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 0),
      child: Row(
        children: [
          if (latest.failed)
            Icon(Icons.error_outline, size: 14, color: colors.red)
          else
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              latest.failed
                  ? 'The application did not respond to /${latest.commandName}.'
                  : 'Sending /${latest.commandName}…',
              style: style.copyWith(
                color: latest.failed ? colors.red : colors.gray,
              ),
            ),
          ),
          if (latest.failed)
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: () => ref
                  .read(interactionTrackerProvider.notifier)
                  .dismiss(latest.id),
              icon: const Icon(Icons.close, size: 14),
            ),
        ],
      ),
    );
  }
}
