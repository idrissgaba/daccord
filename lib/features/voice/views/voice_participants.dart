import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/utils/participant_display.dart';
import 'package:bonfire/features/voice/views/user_volume_menu.dart';
import 'package:bonfire/features/voice/views/voice_moderation_menu.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The list of users present in a voice [channelId], rendered as indented rows
/// beneath the channel tile in the sidebar. Ports the reference client's
/// `voice_channel_item.gd` participant strip: small avatar (green ring while
/// speaking), name in role color, and M/D/V/S flag glyphs.
class VoiceParticipantList extends ConsumerWidget {
  const VoiceParticipantList({
    super.key,
    required this.channelId,
    required this.spaceId,
  });

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucket = ref.watch(
      voiceStatesControllerProvider(
        ref.readActiveServerKey() ?? '',
      ).select((cache) => cache[channelId]),
    );
    if (bucket == null || bucket.isEmpty) return const SizedBox.shrink();

    // Speaking highlights only apply while we're connected to this channel —
    // the speaking set is derived from our own LiveKit room.
    final speaking = ref.watch(
      voiceControllerProvider.select(
        (v) => v.channelId == channelId ? v.speakingUserIds : const <String>{},
      ),
    );

    // The Accord voice state carries no AFK field, so remote members are read
    // from presence (`idle`). Our own row uses the voice controller's flag so it
    // flips immediately, without waiting on the presence round-trip.
    final presences = ref.watch(activePresencesProvider);
    final selfAfk = ref.watch(
      voiceControllerProvider.select(
        (v) => v.channelId == channelId && v.isAfk,
      ),
    );
    final selfUserId = ref.watchUserId();
    final serverKey = ref.readActiveServerKey();
    final moderation = watchVoiceModerationRights(ref, spaceId);

    final members = spaceId == null
        ? null
        : ref.watch(
            accordMembersControllerProvider(
              ref.readActiveServerKey() ?? '',
              spaceId!,
            ),
          );
    final users = ref.watch(
      accordUsersControllerProvider(ref.readActiveServerKey() ?? ''),
    );
    final roles = spaceId == null
        ? const <AccordRole>[]
        : ref.watch(
                spacesControllerProvider.select(
                  (s) => s?.firstWhereOrNull((sp) => sp.id == spaceId)?.roles,
                ),
              ) ??
              const <AccordRole>[];
    final cdnUrl = ref.watchCdnUrl();

    final ensure = ref
        .read(
          accordUsersControllerProvider(
            ref.readActiveServerKey() ?? '',
          ).notifier,
        )
        .ensure;
    final rows =
        [
          for (final vs in bucket.values)
            (
              voiceState: vs,
              display: participantDisplay(
                vs.userId,
                members: members,
                users: users,
                cdnUrl: cdnUrl,
                ensure: ensure,
              ),
            ),
        ]..sort(
          (a, b) => a.display.name.toLowerCase().compareTo(
            b.display.name.toLowerCase(),
          ),
        );

    // Moderators drag participants onto another voice channel to move them
    // (mouse layouts; touch keeps long-press for the menu).
    final dragSpaceId = spaceId;
    final canDrag =
        moderation.move &&
        dragSpaceId != null &&
        serverKey != null &&
        shouldUseDesktopLayout(context);
    Widget draggable(Widget child, String userId, String name) {
      if (!canDrag) return child;
      return Draggable<VoiceMoveDrag>(
        data: VoiceMoveDrag(
          serverKey: serverKey,
          spaceId: dragSpaceId,
          fromChannelId: channelId,
          userId: userId,
          name: name,
        ),
        feedback: Material(
          color: Colors.transparent,
          child: Chip(
            avatar: const Icon(Icons.volume_up, size: 16),
            label: Text(name),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: child),
        child: child,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in rows)
          draggable(
            _ParticipantRow(
              voiceState: row.voiceState,
              display: row.display,
              member: members?[row.voiceState.userId],
              roles: roles,
              speaking: speaking.contains(row.voiceState.userId),
              afk:
                  (selfAfk && row.voiceState.userId == selfUserId) ||
                  accordPresenceStatus(presences, row.voiceState.userId) ==
                      'idle',
              // Our own volume isn't adjustable; everyone else's is, for us only.
              // Moderators also get the voice moderation actions, on any row.
              onOpenVolume:
                  serverKey == null ||
                      (row.voiceState.userId == selfUserId && !moderation.any)
                  ? null
                  : (position) => showUserVolumeMenu(
                      context,
                      serverKey: serverKey,
                      userId: row.voiceState.userId,
                      name: row.display.name,
                      globalPosition: position,
                      spaceId: spaceId,
                      channelId: channelId,
                      showVolume: row.voiceState.userId != selfUserId,
                    ),
            ),
            row.voiceState.userId,
            row.display.name,
          ),
      ],
    );
  }
}

class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.voiceState,
    required this.display,
    required this.member,
    required this.roles,
    required this.speaking,
    required this.afk,
    this.onOpenVolume,
  });

  final AccordVoiceState voiceState;
  final ParticipantDisplay display;
  final AccordMember? member;
  final List<AccordRole> roles;
  final bool speaking;

  /// Away from keyboard: dims the row and adds a moon badge.
  final bool afk;

  /// Opens the local volume menu (right-click position, null on long-press).
  /// Null for our own row.
  final void Function(Offset? position)? onOpenVolume;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final colorRole = member == null ? null : memberColorRole(member!, roles);
    final nameColor =
        (colorRole == null ? null : accordRoleColor(colorRole.color)) ??
        colors.dirtyWhite;

    final openVolume = onOpenVolume;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: openVolume == null
          ? null
          : (d) => openVolume(d.globalPosition),
      onLongPress: openVolume == null ? null : () => openVolume(null),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 1, 8, 1),
        child: Row(
          children: [
            Opacity(
              // Dimmed avatar for an away member, matching how every other chat
              // client signals "present but not here".
              opacity: afk ? 0.4 : 1,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: speaking
                      ? Border.all(color: colors.green, width: 2)
                      : null,
                ),
                padding: const EdgeInsets.all(1),
                child: AccordMemberAvatar(
                  avatarUrl: display.avatarUrl,
                  initial: accordInitial(display.name),
                  radius: 9,
                  backgroundColor: display.color,
                  initialStyle: const TextStyle(fontSize: 9),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                display.name,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: afk ? nameColor.withValues(alpha: 0.5) : nameColor,
                ),
              ),
            ),
            if (afk)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: 'Away',
                  child: Icon(
                    Icons.nightlight_round,
                    size: 11,
                    color: colors.gray,
                    key: const Key('voice-participant-afk'),
                  ),
                ),
              ),
            ..._flags(colors),
          ],
        ),
      ),
    );
  }

  List<Widget> _flags(BonfireThemeExtension colors) {
    final flags = <Widget>[];
    // Moderator-imposed states win over our own toggles, with an icon so they
    // read differently from a self-mute.
    if (voiceState.deaf) {
      flags.add(
        _serverFlag(
          Icons.headset_off,
          'Server deafened',
          colors.red,
          const Key('voice-participant-server-deaf'),
        ),
      );
    } else if (voiceState.mute) {
      flags.add(
        _serverFlag(
          Icons.mic_off,
          'Server muted',
          colors.red,
          const Key('voice-participant-server-mute'),
        ),
      );
    } else if (voiceState.selfDeaf) {
      flags.add(_flag('D', colors.red));
    } else if (voiceState.selfMute) {
      flags.add(_flag('M', colors.red));
    } else if (voiceState.suppress) {
      flags.add(
        _serverFlag(
          Icons.mic_off,
          "Can't speak in this channel",
          colors.gray,
          const Key('voice-participant-suppressed'),
        ),
      );
    }
    if (voiceState.selfVideo) flags.add(_flag('V', colors.green));
    if (voiceState.selfStream) flags.add(_flag('S', colors.primary));
    return flags;
  }

  Widget _serverFlag(IconData icon, String tooltip, Color color, Key key) =>
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, key: key, size: 13, color: color),
        ),
      );

  Widget _flag(String text, Color color) => Padding(
    padding: const EdgeInsets.only(left: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
    ),
  );
}
