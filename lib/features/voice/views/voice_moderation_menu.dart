import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:bonfire/features/voice/views/stage_view.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The voice moderation actions a member's permissions allow.
@immutable
class VoiceModerationRights {
  const VoiceModerationRights({
    this.mute = false,
    this.deafen = false,
    this.move = false,
  });

  factory VoiceModerationRights.from(Set<String> permissions) =>
      VoiceModerationRights(
        mute: accordHasPermission(permissions, AccordPermission.muteMembers),
        deafen: accordHasPermission(
          permissions,
          AccordPermission.deafenMembers,
        ),
        move: accordHasPermission(permissions, AccordPermission.moveMembers),
      );

  static const none = VoiceModerationRights();

  /// Server mute / unmute.
  final bool mute;

  /// Server deafen / undeafen.
  final bool deafen;

  /// Move to another voice channel, and disconnect.
  final bool move;

  bool get any => mute || deafen || move;
}

/// The current user's voice moderation rights in [spaceId] (on the active
/// server), or [VoiceModerationRights.none] outside a space.
VoiceModerationRights watchVoiceModerationRights(
  WidgetRef ref,
  String? spaceId,
) {
  if (spaceId == null) return VoiceModerationRights.none;
  final space = ref.watch(
    spacesControllerProvider.select(
      (spaces) => spaces?.firstWhereOrNull((s) => s.id == spaceId),
    ),
  );
  return VoiceModerationRights.from(ref.watchAccordPermissions(space, spaceId));
}

/// The voice channels of a space a member could be moved to from
/// [currentChannelId], in the order given.
List<AccordChannel> voiceMoveTargets(
  Iterable<AccordChannel> channels,
  String currentChannelId,
) => [
  for (final channel in channels)
    if (isVoiceChannelType(channel.type) && channel.id != currentChannelId)
      channel,
];

/// A participant a moderator is dragging to another voice channel.
@immutable
class VoiceMoveDrag {
  const VoiceMoveDrag({
    required this.serverKey,
    required this.spaceId,
    required this.fromChannelId,
    required this.userId,
    required this.name,
  });

  final String serverKey;
  final String spaceId;
  final String fromChannelId;
  final String userId;
  final String name;

  /// Whether dropping on the voice channel [channelId] of [spaceId] moves
  /// anyone.
  bool canDropOn(String spaceId, String channelId) =>
      spaceId == this.spaceId && channelId != fromChannelId;
}

/// Moves the dragged participant into [channelId], reporting a refusal.
Future<void> moveVoiceParticipant(
  BuildContext context,
  WidgetRef ref,
  VoiceMoveDrag drag,
  String channelId,
) async {
  final client = ref
      .read(accordAuthProvider.notifier)
      .clientForKey(drag.serverKey);
  if (client == null) return;
  final result = await client.members.update(drag.spaceId, drag.userId, {
    'channel_id': channelId,
  });
  if (!result.ok && context.mounted) {
    showInfoSnack(
      context,
      result.errorMessageOr('Couldn’t move ${drag.name}.'),
    );
  }
}

/// Server mute, server deafen, move and disconnect for the participant
/// [userId] in the voice channel [channelId] of [spaceId]. Shows only the
/// actions the current user may take, and nothing without any.
class VoiceModerationPanel extends ConsumerStatefulWidget {
  const VoiceModerationPanel({
    super.key,
    required this.serverKey,
    required this.spaceId,
    required this.channelId,
    required this.userId,
  });

  final String serverKey;
  final String spaceId;
  final String channelId;
  final String userId;

  @override
  ConsumerState<VoiceModerationPanel> createState() =>
      _VoiceModerationPanelState();
}

class _VoiceModerationPanelState extends ConsumerState<VoiceModerationPanel> {
  bool _busy = false;

  /// Sends a member update; closes the menu afterwards when [close].
  Future<void> _update(Map<String, dynamic> body, {bool close = false}) async {
    final client = ref
        .read(accordAuthProvider.notifier)
        .clientForKey(widget.serverKey);
    if (client == null) return;
    setState(() => _busy = true);
    final result = await client.members.update(
      widget.spaceId,
      widget.userId,
      body,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      showInfoSnack(context, result.errorMessageOr('That didn’t work.'));
      return;
    }
    if (close) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final rights = watchVoiceModerationRights(ref, widget.spaceId);
    if (!rights.any) return const SizedBox.shrink();
    final colors = BonfireThemeExtension.of(context);
    final voiceState = ref.watch(
      voiceStatesControllerProvider(
        widget.serverKey,
      ).select((cache) => cache[widget.channelId]?[widget.userId]),
    );
    final stage = watchIsStage(
      ref,
      widget.spaceId,
      widget.channelId,
      serverKey: widget.serverKey,
    );
    final targets = rights.move
        ? voiceMoveTargets(
            ref.watch(
                  accordChannelsControllerProvider(
                    widget.serverKey,
                    widget.spaceId,
                  ),
                ) ??
                const <AccordChannel>[],
            widget.channelId,
          )
        : const <AccordChannel>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        if (rights.mute)
          CheckboxListTile(
            key: const Key('voice-mod-mute'),
            dense: true,
            title: const Text('Server Mute'),
            value: voiceState?.mute ?? false,
            onChanged: _busy
                ? null
                : (value) => _update({'mute': value ?? false}),
          ),
        if (rights.mute && stage && voiceState != null)
          ListTile(
            key: const Key('voice-mod-stage'),
            dense: true,
            enabled: !_busy,
            leading: Icon(
              voiceState.suppress ? Icons.mic_external_on : Icons.group,
              size: 18,
            ),
            title: Text(
              voiceState.suppress ? 'Invite to Speak' : 'Move to Audience',
            ),
            onTap: () async {
              setState(() => _busy = true);
              await updateStage(
                context,
                ref,
                serverKey: widget.serverKey,
                spaceId: widget.spaceId,
                userId: widget.userId,
                suppress: !voiceState.suppress,
              );
              if (mounted) setState(() => _busy = false);
            },
          ),
        if (rights.deafen)
          CheckboxListTile(
            key: const Key('voice-mod-deafen'),
            dense: true,
            title: const Text('Server Deafen'),
            value: voiceState?.deaf ?? false,
            onChanged: _busy
                ? null
                : (value) => _update({'deaf': value ?? false}),
          ),
        if (rights.move && targets.isNotEmpty)
          PopupMenuButton<String>(
            key: const Key('voice-mod-move'),
            enabled: !_busy,
            tooltip: 'Move to another voice channel',
            onSelected: (channelId) =>
                _update({'channel_id': channelId}, close: true),
            itemBuilder: (_) => [
              for (final channel in targets)
                PopupMenuItem(
                  value: channel.id,
                  child: Row(
                    children: [
                      Icon(
                        channel.type == 'stage'
                            ? Icons.podcasts
                            : Icons.volume_up,
                        size: 16,
                        color: colors.gray,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          channel.name ?? channel.id,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: const ListTile(
              dense: true,
              title: Text('Move To'),
              trailing: Icon(Icons.chevron_right, size: 18),
            ),
          ),
        if (rights.move)
          ListTile(
            key: const Key('voice-mod-disconnect'),
            dense: true,
            enabled: !_busy,
            title: Text('Disconnect', style: TextStyle(color: colors.red)),
            onTap: () => _update({'channel_id': null}, close: true),
          ),
      ],
    );
  }
}
