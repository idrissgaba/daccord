import 'dart:async';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/messaging/utils/message_display.dart';
import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:bonfire/features/spaces/utils/search_query.dart';
import 'package:collection/collection.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The channel and message selected from a search result.
class AccordSearchSelection {
  const AccordSearchSelection({
    required this.channelId,
    required this.messageId,
  });
  final String channelId;
  final String messageId;
}

Future<AccordSearchSelection?> showAccordSearch(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<AccordSearchSelection>(
    context: context,
    builder: (_) => _SearchDialog(spaceId: spaceId),
  );
}

class _SearchDialog extends ConsumerStatefulWidget {
  const _SearchDialog({required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<_SearchDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  List<AccordMessage>? _messages;
  List<AccordMember>? _members;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  AccordClient? get _client => ref.accordClient;

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _messages = null;
        _members = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(trimmed));
  }

  /// Turns the typed filters into the search endpoint's parameters: `from:`
  /// resolves against the member cache (username or display name), `in:`
  /// against the channel list; dates and `pinned:` pass straight through.
  Map<String, dynamic> _filterParams(ParsedSearchQuery parsed) {
    final params = <String, dynamic>{};
    final serverKey = ref.readActiveServerKey() ?? '';
    if (parsed.from case final from?) {
      final needle = from.toLowerCase();
      final members = ref.read(
        accordMembersControllerProvider(serverKey, widget.spaceId),
      );
      final member = members?.values.firstWhereOrNull(
        (m) =>
            (m.user?.username.toLowerCase() == needle) ||
            accordMemberName(m).toLowerCase() == needle,
      );
      // An unknown name must match nothing, not everything.
      params['author_id'] = member?.user?.id ?? member?.userId ?? '-';
    }
    if (parsed.inChannel case final name?) {
      final channels = ref.read(
        accordChannelsControllerProvider(serverKey, widget.spaceId),
      );
      final channel = channels?.firstWhereOrNull(
        (c) => (c.name ?? '').toLowerCase() == name.toLowerCase(),
      );
      params['channel_id'] = channel?.id ?? '-';
    }
    if (parsed.before case final before?) params['before'] = before;
    if (parsed.after case final after?) params['after'] = after;
    if (parsed.pinned case final pinned?) params['pinned'] = '$pinned';
    return params;
  }

  Future<void> _run(String query) async {
    final client = _client;
    if (client == null) return;
    final parsed = parseSearchQuery(query);
    final results = await Future.wait([
      client.messages.search(
        widget.spaceId,
        parsed.text,
        query: _filterParams(parsed),
      ),
      client.members.search(
        widget.spaceId,
        parsed.text.isEmpty ? query : parsed.text,
      ),
    ]);
    if (!mounted) return;
    final messageResult = results[0];
    final memberResult = results[1];
    final messageData = messageResult.data;
    final memberData = memberResult.data;
    setState(() {
      _messages = messageResult.ok && messageData is List
          ? messageData.whereType<AccordMessage>().toList()
          : const [];
      _members = memberResult.ok && memberData is List
          ? memberData.whereType<AccordMember>().toList()
          : const [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      onChanged: _onChanged,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText:
                            'Search — from:@user in:#channel before:2026-01-31 pinned:true',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Messages'),
                Tab(text: 'Members'),
              ],
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: LoadingView(),
                    )
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _buildMessages(theme, colors),
                        _buildMembers(theme),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(ThemeData theme, BonfireThemeExtension colors) {
    final messages = _messages;
    if (messages == null) {
      return _hint('Type to search messages', theme);
    }
    if (messages.isEmpty) {
      return _hint('No messages found', theme);
    }
    final serverKey = ref.readActiveServerKey() ?? '';
    final members = ref.watch(
      accordMembersControllerProvider(serverKey, widget.spaceId),
    );
    final channels = ref.watch(
      accordChannelsControllerProvider(serverKey, widget.spaceId),
    );
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final ensureUser = ref
        .read(accordUsersControllerProvider(serverKey).notifier)
        .ensure;
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final message = messages[index];
        final name = accordAuthorName(
          message.authorId,
          members: members,
          users: users,
          ensure: ensureUser,
        );
        final content = plainMessagePreview(
          accordMessageText(message, authorName: name),
        );
        final channelName = channels
            ?.firstWhereOrNull((c) => c.id == message.channelId)
            ?.name;
        return ListTile(
          title: Row(
            children: [
              Flexible(child: Text(name, style: theme.textTheme.titleSmall)),
              const SizedBox(width: 8),
              Text(
                messageTimestampFromIso(message.timestamp),
                style: theme.textTheme.labelSmall!.copyWith(color: colors.gray),
              ),
              if (channelName != null) ...[
                const Spacer(),
                Text(
                  '#$channelName',
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: colors.gray,
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            content.isEmpty ? '(attachment)' : content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(
            AccordSearchSelection(
              channelId: message.channelId,
              messageId: message.id,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMembers(ThemeData theme) {
    final members = _members;
    if (members == null) {
      return _hint('Type to search members', theme);
    }
    if (members.isEmpty) {
      return _hint('No members found', theme);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: members.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final member = members[index];
        return ListTile(
          leading: const Icon(Icons.person_outline, size: 20),
          title: Text(
            accordMemberName(member),
            style: theme.textTheme.titleSmall,
          ),
        );
      },
    );
  }

  Widget _hint(String text, ThemeData theme) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(child: Text(text, style: theme.textTheme.bodyMedium)),
  );
}
