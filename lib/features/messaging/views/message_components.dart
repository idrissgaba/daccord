import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/app_commands.dart';
import 'package:bonfire/features/messaging/utils/interaction_logic.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/external_url.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The buttons and select menus of a bot's message. Using one sends an
/// interaction to the bot; the control spins until the bot answers, and a
/// note says so when it doesn't.
class MessageComponentsView extends ConsumerWidget {
  const MessageComponentsView({super.key, required this.message});

  final AccordMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = parseComponents(message.components);
    if (rows.isEmpty) return const SizedBox.shrink();
    final colors = BonfireThemeExtension.of(context);
    final pending = ref.watch(
      interactionTrackerProvider.select(
        (all) => all.values.where((p) => p.messageId == message.id).toList(),
      ),
    );
    final failed = pending.any((p) => p.failed);

    Future<void> use(String customId, {List<String>? values}) async {
      final client = ref.accordClient;
      if (client == null) return;
      final result = await client.interactions.useComponent(
        channelId: message.channelId,
        messageId: message.id,
        customId: customId,
        values: values,
      );
      if (!context.mounted) return;
      final id = result.ok && result.data is Map
          ? (result.data as Map)['id'] as String?
          : null;
      if (id == null) {
        showInfoSnack(context, result.errorMessageOr('That didn’t work.'));
        return;
      }
      ref
          .read(interactionTrackerProvider.notifier)
          .started(
            PendingInteraction(
              id: id,
              channelId: message.channelId,
              messageId: message.id,
              customId: customId,
            ),
          );
    }

    bool busy(String? customId) =>
        customId != null &&
        pending.any((p) => p.customId == customId && !p.failed);

    return Padding(
      key: ValueKey('message-components-${message.id}'),
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final component in row)
                    switch (component) {
                      ComponentButton() => _Button(
                        button: component,
                        busy: busy(component.customId),
                        onPressed: component.style == ComponentButtonStyle.link
                            ? () => openExternalUrl(context, component.url)
                            : () => use(component.customId!),
                      ),
                      ComponentSelect() => _Select(
                        select: component,
                        busy: busy(component.customId),
                        onSubmit: (values) =>
                            use(component.customId, values: values),
                      ),
                    },
                ],
              ),
            ),
          if (failed)
            Text(
              'This interaction failed',
              key: const Key('interaction-failed'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: colors.red),
            ),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.button,
    required this.busy,
    required this.onPressed,
  });

  final ComponentButton button;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final background = switch (button.style) {
      ComponentButtonStyle.primary => colors.primary,
      ComponentButtonStyle.success => colors.green,
      ComponentButtonStyle.danger => colors.red,
      _ => colors.foreground,
    };
    final label = [
      if (button.emoji != null) button.emoji!,
      if (button.label.isNotEmpty) button.label,
    ].join(' ');
    return FilledButton(
      key: ValueKey('component-${button.customId ?? button.url}'),
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: Colors.white,
        disabledBackgroundColor: background.withValues(alpha: 0.5),
        disabledForegroundColor: Colors.white70,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      onPressed: button.disabled || busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                if (button.style == ComponentButtonStyle.link) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new, size: 14),
                ],
              ],
            ),
    );
  }
}

class _Select extends StatelessWidget {
  const _Select({
    required this.select,
    required this.busy,
    required this.onSubmit,
  });

  final ComponentSelect select;
  final bool busy;
  final ValueChanged<List<String>> onSubmit;

  Future<void> _pickMany(BuildContext context) async {
    final chosen = <String>{
      for (final option in select.options)
        if (option.isDefault) option.value,
    };
    final picked = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: Text(select.placeholder ?? 'Choose'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in select.options)
                  CheckboxListTile(
                    value: chosen.contains(option.value),
                    title: Text(
                      [
                        if (option.emoji != null) option.emoji!,
                        option.label,
                      ].join(' '),
                    ),
                    subtitle: option.description == null
                        ? null
                        : Text(option.description!),
                    onChanged: (on) => setInner(() {
                      if (on == true && chosen.length < select.maxValues) {
                        chosen.add(option.value);
                      } else {
                        chosen.remove(option.value);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: chosen.length < select.minValues
                  ? null
                  : () => Navigator.of(ctx).pop(chosen.toList()),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) onSubmit(picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final selected = select.options.firstWhereOrNull((o) => o.isDefault);
    if (select.maxValues > 1) {
      return OutlinedButton.icon(
        key: ValueKey('component-${select.customId}'),
        onPressed: select.disabled || busy ? null : () => _pickMany(context),
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.checklist, size: 16),
        label: Text(select.placeholder ?? 'Choose'),
      );
    }
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: colors.foreground),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey('component-${select.customId}'),
          isExpanded: true,
          value: selected?.value,
          hint: Text(select.placeholder ?? 'Make a selection'),
          onChanged: select.disabled || busy
              ? null
              : (value) {
                  if (value != null) onSubmit([value]);
                },
          items: [
            for (final option in select.options)
              DropdownMenuItem(
                value: option.value,
                child: Text(
                  [
                    if (option.emoji != null) option.emoji!,
                    option.label,
                  ].join(' '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "↳ Ada used /play" above a bot's answer to a command.
class MessageInteractionHeader extends ConsumerWidget {
  const MessageInteractionHeader({
    super.key,
    required this.interaction,
    required this.serverKey,
    this.spaceId,
  });

  final AccordMessageInteraction interaction;
  final String serverKey;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final spaceId = this.spaceId;
    final member = spaceId == null
        ? null
        : ref.watch(
            accordMembersControllerProvider(
              serverKey,
              spaceId,
            ).select((members) => members?[interaction.userId]),
          );
    final user = ref.watch(
      accordUsersControllerProvider(
        serverKey,
      ).select((users) => users[interaction.userId]),
    );
    final name = member != null
        ? accordMemberName(member)
        : accordUserName(user, fallback: 'Someone');
    final style = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: colors.gray);
    return Padding(
      key: ValueKey('interaction-header-${interaction.id}'),
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 14, color: colors.gray),
          const SizedBox(width: 4),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: name,
                    style: style.copyWith(color: colors.dirtyWhite),
                  ),
                  TextSpan(
                    text: interaction.name == null
                        ? ' used a component'
                        : ' used ',
                  ),
                  if (interaction.name != null)
                    TextSpan(
                      text: '/${interaction.name}',
                      style: style.copyWith(color: colors.primary),
                    ),
                ],
              ),
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bot is thinking…" while a bot prepares its answer.
class MessageThinking extends StatelessWidget {
  const MessageThinking({super.key, required this.botName});

  final String botName;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      key: const Key('message-thinking'),
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '$botName is thinking…',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: colors.gray,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Only you can see this · Dismiss message" under an ephemeral answer.
class EphemeralFooter extends StatelessWidget {
  const EphemeralFooter({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final style = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: colors.gray);
    return Padding(
      key: const Key('ephemeral-footer'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_outlined, size: 14, color: colors.gray),
          const SizedBox(width: 4),
          Text('Only you can see this · ', style: style),
          InkWell(
            key: const Key('ephemeral-dismiss'),
            onTap: onDismiss,
            child: Text(
              'Dismiss message',
              style: style.copyWith(
                color: colors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
