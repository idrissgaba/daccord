import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Channel types a webhook can post in.
bool webhookPostable(AccordChannel channel) =>
    channel.type == 'text' || channel.type == 'announcement';

/// The text channels of a space a webhook can post in, in the order given.
List<AccordChannel> webhookChannels(Iterable<AccordChannel> channels) => [
  for (final channel in channels)
    if (webhookPostable(channel)) channel,
];

/// Opens the space's webhooks: create one per text channel, copy its URL,
/// rename, move, change the avatar, delete. Gated on `manage_webhooks` at the
/// call site (space settings).
Future<void> showAccordWebhooks(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AccordWebhooksDialog(spaceId: spaceId),
  );
}

class AccordWebhooksDialog extends ConsumerStatefulWidget {
  const AccordWebhooksDialog({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<AccordWebhooksDialog> createState() =>
      _AccordWebhooksDialogState();
}

class _AccordWebhooksDialogState extends ConsumerState<AccordWebhooksDialog> {
  List<AccordWebhook>? _webhooks;
  bool _busy = false;
  String? _error;

  AccordClient? get _client => ref.accordClient;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = _client;
    if (client == null) return;
    final result = await client.webhooks.listForSpace(widget.spaceId);
    if (!mounted) return;
    setState(() {
      _webhooks = result.ok
          ? (result.data as List).whereType<AccordWebhook>().toList()
          : const [];
      _error = result.ok
          ? null
          : result.errorMessageOr('Could not load webhooks');
    });
  }

  /// Runs a webhook change and reloads the list after it.
  Future<void> _run(
    Future<RestResult> Function(AccordClient) action,
    String failure,
  ) async {
    final client = _client;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action(client);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.errorMessageOr(failure);
    });
    if (result.ok) await _load();
  }

  Future<void> _create(List<AccordChannel> channels) async {
    if (channels.isEmpty) return;
    final channelId = await _pickChannel(channels, title: 'New webhook in…');
    if (channelId == null || !mounted) return;
    await _run(
      (client) => client.webhooks.create(channelId, name: 'Webhook'),
      'Could not create the webhook',
    );
  }

  Future<String?> _pickChannel(
    List<AccordChannel> channels, {
    required String title,
    String? current,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final channel in channels)
            SimpleDialogOption(
              key: ValueKey('webhook-channel-${channel.id}'),
              onPressed: () => Navigator.of(ctx).pop(channel.id),
              child: Row(
                children: [
                  const Icon(Icons.tag, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(channel.name ?? channel.id)),
                  if (channel.id == current) const Icon(Icons.check, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _rename(AccordWebhook webhook) async {
    final name = (await showTextPromptDialog(
      context,
      title: 'Rename webhook',
      label: 'Name',
      initial: webhook.name,
    ))?.trim();
    if (name == null || name.isEmpty || name == webhook.name) return;
    await _run(
      (client) => client.webhooks.update(webhook.id, name: name),
      'Could not rename the webhook',
    );
  }

  Future<void> _move(
    AccordWebhook webhook,
    List<AccordChannel> channels,
  ) async {
    final channelId = await _pickChannel(
      channels,
      title: 'Post in…',
      current: webhook.channelId,
    );
    if (channelId == null || channelId == webhook.channelId) return;
    await _run(
      (client) => client.webhooks.update(webhook.id, channelId: channelId),
      'Could not move the webhook',
    );
  }

  Future<void> _changeAvatar(AccordWebhook webhook) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    await _run(
      (client) => client.webhooks.update(
        webhook.id,
        avatar: AccordCDN.buildDataUri(bytes, file.name),
      ),
      'Could not change the avatar',
    );
  }

  Future<void> _copyUrl(AccordWebhook webhook) async {
    final client = _client;
    final url = client == null ? null : webhook.executeUrl(client.rest.baseUrl);
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    showInfoSnack(context, 'Webhook URL copied');
  }

  Future<void> _delete(AccordWebhook webhook) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${webhook.name}?',
      message:
          'Anything posting to its URL will stop working. '
          'Messages it already posted stay.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true || !mounted) return;
    await _run(
      (client) => client.webhooks.delete(webhook.id),
      'Could not delete the webhook',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final cdnUrl = ref.watchCdnUrl();
    final channels = webhookChannels(
      ref.watch(
            accordChannelsControllerProvider(
              ref.readActiveServerKey() ?? '',
              widget.spaceId,
            ),
          ) ??
          const [],
    );
    String channelName(String id) =>
        channels.where((c) => c.id == id).firstOrNull?.name ??
        'unknown channel';
    final webhooks = _webhooks;

    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.webhook, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Webhooks', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              Text(
                'Services post into a channel through a webhook\'s URL — '
                'monitoring alerts, download notifications, CI results. '
                'Keep the URL secret: anyone with it can post.',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('webhook-create'),
                onPressed: _busy || channels.isEmpty
                    ? null
                    : () => _create(channels),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New webhook'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                InlineError(_error!, centered: false),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: webhooks == null
                    ? const LoadingView()
                    : webhooks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No webhooks yet.',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: webhooks.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final webhook = webhooks[index];
                          final avatarUrl = accordAvatarUrl(
                            AccordUser(
                              id: webhook.userId,
                              username: webhook.name,
                              avatar: webhook.avatar,
                            ),
                            cdnUrl,
                          );
                          return ListTile(
                            key: ValueKey('webhook-${webhook.id}'),
                            contentPadding: EdgeInsets.zero,
                            leading: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _busy
                                  ? null
                                  : () => _changeAvatar(webhook),
                              child: Tooltip(
                                message: 'Change avatar',
                                child: AccordMemberAvatar(
                                  avatarUrl: avatarUrl,
                                  initial: accordInitial(webhook.name),
                                  radius: 18,
                                ),
                              ),
                            ),
                            title: Text(webhook.name),
                            subtitle: Text(
                              '#${channelName(webhook.channelId)}',
                            ),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  key: ValueKey('webhook-copy-${webhook.id}'),
                                  tooltip: 'Copy webhook URL',
                                  onPressed: () => _copyUrl(webhook),
                                  icon: const Icon(Icons.link, size: 18),
                                ),
                                PopupMenuButton<String>(
                                  key: ValueKey('webhook-menu-${webhook.id}'),
                                  enabled: !_busy,
                                  tooltip: 'More',
                                  onSelected: (action) => switch (action) {
                                    'rename' => _rename(webhook),
                                    'move' => _move(webhook, channels),
                                    'avatar' => _changeAvatar(webhook),
                                    _ => _delete(webhook),
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'move',
                                      child: Text('Change channel'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'avatar',
                                      child: Text('Change avatar'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(
                                        'Delete',
                                        style: TextStyle(color: colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
