import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/utils/forward_message.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/in_app_links.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Asks where to forward [message] (a channel of this space or a direct
/// message), with an optional comment, then posts it there: the text as a
/// quoted snapshot under a "Forwarded" line, its files re-uploaded.
Future<void> showForwardMessageDialog(
  BuildContext context, {
  required AccordMessage message,
  required String authorName,
  required String sourceLabel,
  String? spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ForwardMessageDialog(
      message: message,
      authorName: authorName,
      sourceLabel: sourceLabel,
      spaceId: spaceId,
    ),
  );
}

class _Destination {
  const _Destination(this.channelId, this.label, this.icon);

  final String channelId;
  final String label;
  final IconData icon;
}

class _ForwardMessageDialog extends ConsumerStatefulWidget {
  const _ForwardMessageDialog({
    required this.message,
    required this.authorName,
    required this.sourceLabel,
    this.spaceId,
  });

  final AccordMessage message;
  final String authorName;
  final String sourceLabel;
  final String? spaceId;

  @override
  ConsumerState<_ForwardMessageDialog> createState() =>
      _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends ConsumerState<_ForwardMessageDialog> {
  final _filter = TextEditingController();
  final _comment = TextEditingController();
  String? _selected;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDms());
  }

  @override
  void dispose() {
    _filter.dispose();
    _comment.dispose();
    super.dispose();
  }

  /// Direct messages are only fetched when the DM list was opened; load them
  /// here too so they can be picked.
  Future<void> _loadDms() async {
    final serverKey = ref.readActiveServerKey();
    final client = ref.accordClient;
    if (serverKey == null || client == null) return;
    if (ref.read(dmChannelsControllerProvider(serverKey)) != null) return;
    final result = await client.users.listChannels();
    if (!mounted) return;
    final data = result.data;
    if (result.ok && data is List) {
      ref
          .read(dmChannelsControllerProvider(serverKey).notifier)
          .setChannels(data.whereType<AccordChannel>().toList());
    }
  }

  List<_Destination> _destinations(String serverKey) {
    final spaceId = widget.spaceId;
    final channels = spaceId == null
        ? const <AccordChannel>[]
        : ref.watch(accordChannelsControllerProvider(serverKey, spaceId)) ??
              const <AccordChannel>[];
    final dms =
        ref.watch(dmChannelsControllerProvider(serverKey)) ??
        const <AccordChannel>[];
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final selfId = ref.readUserId();
    return [
      for (final channel in channels)
        if (channel.type == 'text' || channel.type == 'announcement')
          _Destination(channel.id, '#${channel.name ?? channel.id}', Icons.tag),
      for (final dm in dms)
        _Destination(
          dm.id,
          dmChannelTitle(dm, selfId, fallback: 'Direct message', users: users),
          Icons.person_outline,
        ),
    ];
  }

  Future<void> _forward() async {
    final destination = _selected;
    final serverKey = ref.readActiveServerKey();
    final client = ref.accordClient;
    if (destination == null || serverKey == null || client == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final message = widget.message;
    final spaceId = widget.spaceId ?? message.spaceId;
    final content = forwardedMessageContent(
      original: message.content,
      authorName: widget.authorName,
      sourceLabel: widget.sourceLabel,
      link: spaceId == null
          ? null
          : messageLink(
              spaceId: spaceId,
              channelId: message.channelId,
              messageId: message.id,
            ),
      comment: _comment.text,
    );

    // Re-upload the files; end-to-end encrypted ones stay where they are
    // (their bytes are ciphertext for the original conversation only).
    final files = <Map<String, dynamic>>[];
    var skipped = 0;
    final cdnUrl = ref.readCdnUrl() ?? '';
    for (final attachment in message.attachments) {
      if (attachment.encryption != null) {
        skipped++;
        continue;
      }
      try {
        final response = await http.get(
          Uri.parse(AccordCDN.resolvePath(attachment.url, cdnUrl: cdnUrl)),
        );
        if (response.statusCode != 200) {
          skipped++;
          continue;
        }
        files.add({
          'filename': attachment.filename,
          'content': response.bodyBytes,
          'content_type': attachment.contentType ?? 'application/octet-stream',
        });
      } catch (_) {
        skipped++;
      }
    }

    final failure = await ref
        .read(accordMessagesControllerProvider(serverKey, destination).notifier)
        .sendWithAttachments(client, content, files);
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _sending = false;
        _error = failure.message;
      });
      return;
    }
    Navigator.of(context).pop();
    showInfoSnack(
      context,
      skipped == 0
          ? 'Message forwarded'
          : 'Message forwarded ($skipped file${skipped == 1 ? '' : 's'} '
                'could not be forwarded)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.readActiveServerKey() ?? '';
    final query = _filter.text.trim().toLowerCase();
    final destinations = _destinations(
      serverKey,
    ).where((d) => d.label.toLowerCase().contains(query)).toList();

    return AlertDialog(
      title: const Text('Forward message'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('forward-filter'),
              controller: _filter,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search channels and direct messages',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: destinations.isEmpty
                  ? Center(
                      child: Text(
                        'No matching destination',
                        style: TextStyle(color: colors.gray),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final d in destinations)
                          ListTile(
                            key: ValueKey('forward-to-${d.channelId}'),
                            dense: true,
                            leading: Icon(d.icon, size: 18),
                            title: Text(
                              d.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _selected == d.channelId,
                            trailing: _selected == d.channelId
                                ? Icon(Icons.check, color: colors.primary)
                                : null,
                            onTap: _sending
                                ? null
                                : () => setState(() => _selected = d.channelId),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('forward-comment'),
              controller: _comment,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                hintText: 'Add a message (optional)',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('forward-send'),
          onPressed: _selected == null || _sending ? null : _forward,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Forward'),
        ),
      ],
    );
  }
}
