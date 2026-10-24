import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/utils/participant_display.dart';
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:bonfire/features/voice/views/voice_moderation_menu.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether [channelId] of [spaceId] (on [serverKey], or the active server) is
/// a stage.
bool watchIsStage(
  WidgetRef ref,
  String? spaceId,
  String channelId, {
  String? serverKey,
}) {
  if (spaceId == null) return false;
  return ref.watch(
    accordChannelsControllerProvider(
      serverKey ?? ref.watchActiveServerKey() ?? '',
      spaceId,
    ).select(
      (channels) =>
          channels?.firstWhereOrNull((c) => c.id == channelId)?.type == 'stage',
    ),
  );
}

/// Sends a stage update for [userId] (`@me` for yourself), reporting a refusal.
Future<bool> updateStage(
  BuildContext context,
  WidgetRef ref, {
  required String serverKey,
  required String spaceId,
  required String userId,
  bool? suppress,
  bool? requestToSpeak,
}) async {
  final client = ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
  if (client == null) return false;
  final result = await client.voice.updateStage(
    spaceId,
    userId,
    suppress: suppress,
    requestToSpeak: requestToSpeak,
  );
  if (!result.ok && context.mounted) {
    showInfoSnack(context, result.errorMessageOr('That didn’t work.'));
  }
  return result.ok;
}

/// The stage's audience under the speakers: raised hands first, each with an
/// "Invite" button for stage moderators.
class StageAudiencePanel extends ConsumerWidget {
  const StageAudiencePanel({
    super.key,
    required this.channelId,
    required this.spaceId,
  });

  final String channelId;
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final states =
        ref
            .watch(
              voiceStatesControllerProvider(
                serverKey,
              ).select((cache) => cache[channelId]),
            )
            ?.values ??
        const <AccordVoiceState>[];
    final audience = stageAudience(states);
    final moderator = watchVoiceModerationRights(ref, spaceId).mute;
    final members = ref.watch(
      accordMembersControllerProvider(serverKey, spaceId),
    );
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final cdnUrl = ref.watchCdnUrl();
    final ensure = ref
        .read(accordUsersControllerProvider(serverKey).notifier)
        .ensure;

    return Container(
      key: const Key('stage-audience'),
      constraints: const BoxConstraints(maxHeight: 180),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.foreground)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'AUDIENCE — ${audience.length}',
            style: theme.textTheme.labelSmall!.copyWith(
              color: colors.gray,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final vs in audience)
                    _AudienceChip(
                      key: ValueKey('stage-audience-${vs.userId}'),
                      display: participantDisplay(
                        vs.userId,
                        members: members,
                        users: users,
                        cdnUrl: cdnUrl,
                        ensure: ensure,
                      ),
                      raised: vs.requestToSpeakTimestamp != null,
                      onInvite: moderator
                          ? () => updateStage(
                              context,
                              ref,
                              serverKey: serverKey,
                              spaceId: spaceId,
                              userId: vs.userId,
                              suppress: false,
                            )
                          : null,
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

class _AudienceChip extends StatelessWidget {
  const _AudienceChip({
    super.key,
    required this.display,
    required this.raised,
    required this.onInvite,
  });

  final ParticipantDisplay display;
  final bool raised;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: colors.foreground,
        borderRadius: BorderRadius.circular(16),
        border: raised ? Border.all(color: colors.primary) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AccordMemberAvatar(
            avatarUrl: display.avatarUrl,
            initial: display.name.isEmpty ? '?' : display.name.characters.first,
            radius: 12,
            backgroundColor: display.color,
            initialStyle: const TextStyle(fontSize: 11),
          ),
          const SizedBox(width: 6),
          Text(display.name, style: Theme.of(context).textTheme.bodySmall),
          if (raised) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.back_hand,
              size: 14,
              color: colors.primary,
              semanticLabel: 'Hand raised',
            ),
          ],
          if (onInvite != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onInvite,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Invite',
                  style: TextStyle(color: colors.primary, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
