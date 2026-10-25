import 'dart:async' show unawaited;

import 'package:accordkit/accordkit.dart'
    show AccordMember, AccordUser, AccordVoiceState;
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart'
    show VoiceSession;
import 'package:bonfire/features/voice/utils/participant_display.dart';
import 'package:bonfire/features/voice/utils/audio_output_support.dart';
import 'package:bonfire/features/voice/views/user_volume_menu.dart';
import 'package:bonfire/features/voice/views/voice_moderation_menu.dart';
import 'package:bonfire/features/voice/views/stage_view.dart';
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/features/voice/views/screen_share_picker.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/features/voice/views/voice_text_panel.dart';
import 'package:bonfire/shared/components/horizontal_wheel_scroll.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:bonfire/features/member/views/accord_member_avatar.dart';
import 'package:bonfire/features/voice/views/voice_lobby.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import 'package:livekit_client/livekit_client.dart' as lk;

/// Presents the voice channel full-screen as its own route, rendering
/// [VoiceChannelView] in [VoiceChannelView.fullScreen] mode so its header
/// shows a "minimize" button that pops back.
/// How many full-screen voice views are open. While one is, the views under
/// it (and the PiP) stop rendering video: flutter_webrtc on Windows crashes
/// when one track feeds two renderers and one of them is torn down.
final voiceFullScreenOpen = ValueNotifier<int>(0);

Future<void> showFullScreenVoice(
  BuildContext context, {
  required String channelId,
  required String? spaceId,
  required String? channelName,
}) async {
  voiceFullScreenOpen.value += 1;
  try {
    await _pushFullScreenVoice(
      context,
      channelId: channelId,
      spaceId: spaceId,
      channelName: channelName,
    );
  } finally {
    voiceFullScreenOpen.value -= 1;
  }
}

Future<void> _pushFullScreenVoice(
  BuildContext context, {
  required String channelId,
  required String? spaceId,
  required String? channelName,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        body: SafeArea(
          child: VoiceChannelView(
            channelId: channelId,
            spaceId: spaceId,
            channelName: channelName,
            fullScreen: true,
          ),
        ),
      ),
    ),
  );
}

/// The voice channel screen shown in the message pane: a header, the video
/// grid (one tile per participant, camera/screen tracks or an initials
/// placeholder), an optional side text-chat panel, and a control bar
/// (reference: `main_window_voice_view.gd`).
class VoiceChannelView extends ConsumerStatefulWidget {
  const VoiceChannelView({
    super.key,
    required this.channelId,
    required this.spaceId,
    required this.channelName,
    this.fullScreen = false,
  });

  final String channelId;
  final String? spaceId;
  final String? channelName;

  /// Whether this is the pushed full-screen presentation (see
  /// [showFullScreenVoice]). Swaps the header's maximize button for a minimize
  /// button that pops the route.
  final bool fullScreen;

  @override
  ConsumerState<VoiceChannelView> createState() => _VoiceChannelViewState();
}

class _VoiceChannelViewState extends ConsumerState<VoiceChannelView> {
  String? _spotlightUserId;

  /// Whether the voice text-chat panel is open. Defaults open in full-screen and
  /// in the lobby, and closed for a call already in progress in the narrower
  /// message-pane presentation; the header toggle then wins until the view
  /// switches to another channel.
  late bool _chatOpen = _defaultChatOpen();

  /// Below this width the chat panel takes over the body instead of sitting
  /// beside the video grid.
  static const double _sidePanelBreakpoint = 720;

  bool _defaultChatOpen() {
    final connectedHere =
        ref.read(voiceControllerProvider).channelId == widget.channelId;
    return widget.fullScreen || !connectedHere;
  }

  @override
  void didUpdateWidget(covariant VoiceChannelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The message pane reuses one [VoiceChannelView] across channel switches, so
    // per-channel view state has to be re-derived rather than carried over.
    if (oldWidget.channelId != widget.channelId) {
      _spotlightUserId = null;
      _chatOpen = _defaultChatOpen();
    }
  }

  /// Whether this is a DM/group-DM call (no parent space). DM calls layer the
  /// ring/accept/decline signaling on top of the plain voice session.
  bool get _isDmCall => widget.spaceId == null;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final connectedHere = ref.watch(
      voiceControllerProvider.select((v) => v.channelId == widget.channelId),
    );

    // A DM call presented full-screen pops itself once the call ends (we leave,
    // the peer declines, or the room empties) rather than stranding the user on
    // an un-rejoinable DM lobby.
    if (widget.fullScreen && _isDmCall) {
      ref.listen(voiceControllerProvider.select((v) => v.channelId), (
        prev,
        next,
      ) {
        if (prev == widget.channelId && next != widget.channelId && mounted) {
          Navigator.of(context).maybePop();
        }
      });
    }

    final ringing =
        _isDmCall &&
        connectedHere &&
        ref.watch(
          callControllerProvider.select(
            (s) => s.outgoingChannelId == widget.channelId,
          ),
        );

    return Container(
      color: colors.background,
      child: Column(
        children: [
          _header(context, colors),
          if (ringing) _RingingBanner(name: widget.channelName),
          Expanded(child: _body(connectedHere)),
          if (connectedHere)
            _ControlBar(channelId: widget.channelId, spaceId: widget.spaceId),
        ],
      ),
    );
  }

  Widget _body(bool connectedHere) {
    final primary = connectedHere
        ? _ConnectedBody(
            channelId: widget.channelId,
            spaceId: widget.spaceId,
            fullScreen: widget.fullScreen,
            spotlightUserId: _spotlightUserId,
            onToggleSpotlight: (userId) => setState(
              () =>
                  _spotlightUserId = _spotlightUserId == userId ? null : userId,
            ),
          )
        : VoiceLobbyBody(
            channelId: widget.channelId,
            spaceId: widget.spaceId,
            channelName: widget.channelName,
          );

    if (!_chatOpen) return primary;

    final chat = VoiceTextPanel(
      channelId: widget.channelId,
      spaceId: widget.spaceId,
      channelName: widget.channelName,
      onClose: () => setState(() => _chatOpen = false),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Wide: chat sits beside the video grid / lobby.
        if (constraints.maxWidth >= _sidePanelBreakpoint) {
          return Row(
            children: [
              Expanded(child: primary),
              // Wide enough for the full message pane's chrome (avatar gutter,
              // reactions, floating action bar) to stay readable.
              SizedBox(width: 340, child: chat),
            ],
          );
        }
        // Narrow, in a call: chat takes over the body. The video grid is the
        // thing being traded away, and every call control still lives in the
        // control bar below.
        if (connectedHere) return chat;
        // Narrow, in the lobby: chat still takes the body, but the participants
        // and the Join button stay pinned above it.
        return Column(
          children: [
            VoiceLobbyBody(
              channelId: widget.channelId,
              spaceId: widget.spaceId,
              channelName: widget.channelName,
              compact: true,
            ),
            Expanded(child: chat),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, BonfireThemeExtension colors) {
    return Container(
      height: 48,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.foreground, width: 1)),
      ),
      child: Row(
        children: [
          Icon(
            watchIsStage(ref, widget.spaceId, widget.channelId)
                ? Icons.podcasts
                : Icons.volume_up,
            size: 18,
            color: colors.dirtyWhite,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.channelName ?? '',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            tooltip: _chatOpen ? 'Hide chat' : 'Show chat',
            onPressed: () => setState(() => _chatOpen = !_chatOpen),
            icon: Icon(
              _chatOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
              size: 18,
              color: _chatOpen ? colors.primary : colors.dirtyWhite,
            ),
          ),
          IconButton(
            tooltip: widget.fullScreen ? 'Exit full screen' : 'Full screen',
            onPressed: () {
              if (widget.fullScreen) {
                Navigator.of(context).maybePop();
              } else {
                showFullScreenVoice(
                  context,
                  channelId: widget.channelId,
                  spaceId: widget.spaceId,
                  channelName: widget.channelName,
                );
              }
            },
            icon: Icon(
              widget.fullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              size: 20,
              color: colors.dirtyWhite,
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin banner shown while an outgoing DM call is still ringing (the callee
/// hasn't joined yet).
class _RingingBanner extends StatelessWidget {
  const _RingingBanner({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.foreground,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.dirtyWhite,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              name == null || name!.isEmpty ? 'Calling…' : 'Calling $name…',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(color: colors.dirtyWhite),
            ),
          ),
        ],
      ),
    );
  }
}

/// A renderable tile: either a video track or a placeholder for [userId].
class _Tile {
  const _Tile({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.bg,
    required this.track,
    required this.isScreen,
    required this.muted,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final Color bg;
  final VideoTrack? track;
  final bool isScreen;
  final bool muted;

  /// Which tile is spotlighted: a person has a camera tile and, while
  /// sharing, a screen tile — by user id alone the camera tile won, so
  /// opening someone's screen share showed their avatar instead.
  String get spotlightKey => '$userId:${isScreen ? 'screen' : 'camera'}';
}

/// The in-call body: the video grid (or spotlight + strip).
class _ConnectedBody extends ConsumerWidget {
  const _ConnectedBody({
    required this.channelId,
    required this.spaceId,
    required this.spotlightUserId,
    required this.onToggleSpotlight,
    this.only,
    this.fullScreen = false,
  });

  /// This is the full-screen view, the one that keeps rendering video while
  /// it is open (see [voiceFullScreenOpen]).
  final bool fullScreen;

  final String channelId;
  final String? spaceId;
  final String? spotlightUserId;
  final ValueChanged<String> onToggleSpotlight;

  /// Only these participants get tiles (a stage's speakers); everyone when
  /// null. Set, the body is laid out as a plain call.
  final Set<String>? only;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuild on any room change (track added/removed, speaker changes).
    ref.watch(voiceControllerProvider.select((v) => v.tick));
    final states =
        ref
            .watch(
              voiceStatesControllerProvider(
                ref.readActiveServerKey() ?? '',
              ).select((cache) => cache[channelId]),
            )
            ?.values ??
        const [];
    final speaking = ref.watch(
      voiceControllerProvider.select((v) => v.speakingUserIds),
    );
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
    final cdnUrl = ref.watchCdnUrl();
    final myId = ref.watchUserId();
    final session = ref.read(voiceControllerProvider.notifier).session;
    final stage = only == null && watchIsStage(ref, spaceId, channelId);
    if (stage) {
      final speakers = stageSpeakers(states);
      return Column(
        children: [
          Expanded(
            child: speakers.isEmpty
                ? const Center(child: Text('No one is on stage yet.'))
                : _ConnectedBody(
                    channelId: channelId,
                    spaceId: spaceId,
                    spotlightUserId: spotlightUserId,
                    onToggleSpotlight: onToggleSpotlight,
                    only: {for (final s in speakers) s.userId},
                    fullScreen: fullScreen,
                  ),
          ),
          StageAudiencePanel(channelId: channelId, spaceId: spaceId!),
        ],
      );
    }

    final tiles = _buildTiles(
      states: only == null
          ? states
          : states.where((s) => only!.contains(s.userId)),
      members: members,
      users: users,
      cdnUrl: cdnUrl,
      ensure: ref
          .read(
            accordUsersControllerProvider(
              ref.readActiveServerKey() ?? '',
            ).notifier,
          )
          .ensure,
      myId: myId,
      session: session,
    );

    if (tiles.isEmpty) {
      return const Center(child: Text('Connecting…'));
    }

    final serverKey = ref.readActiveServerKey();
    final moderation = watchVoiceModerationRights(ref, spaceId);
    Widget tileWidget(_Tile t) => _VideoTile(
      key: ValueKey('${t.userId}:${t.isScreen}'),
      fullScreen: fullScreen,
      tile: t,
      speaking: speaking.contains(t.userId),
      spotlighted: spotlightUserId == t.spotlightKey,
      onDoubleTap: () => onToggleSpotlight(t.spotlightKey),
      onOpenVolume: serverKey == null || (t.userId == myId && !moderation.any)
          ? null
          : (position) => showUserVolumeMenu(
              context,
              serverKey: serverKey,
              userId: t.userId,
              name: t.name,
              globalPosition: position,
              spaceId: spaceId,
              channelId: channelId,
              showVolume: t.userId != myId,
            ),
    );

    // Spotlight a chosen tile (or any active screen-share) above a strip.
    final spotlightIdx = spotlightUserId != null
        ? tiles.indexWhere((t) => t.spotlightKey == spotlightUserId)
        : _defaultSpotlight(tiles, myId);
    if (spotlightIdx >= 0 && tiles.length > 1) {
      return _SpotlightLayout(
        spotlight: tiles[spotlightIdx],
        rest: [
          for (var i = 0; i < tiles.length; i++)
            if (i != spotlightIdx) tiles[i],
        ],
        tileBuilder: tileWidget,
      );
    }

    return _GridLayout(tiles: tiles, tileBuilder: tileWidget);
  }

  /// Builds one [_Tile] per participant (plus one per active screen share) —
  /// pure data assembly, no widgets.
  List<_Tile> _buildTiles({
    required Iterable<AccordVoiceState> states,
    required Map<String, AccordMember>? members,
    required Map<String, AccordUser>? users,
    required String? cdnUrl,
    required void Function(String) ensure,
    required String? myId,
    required VoiceSession? session,
  }) {
    final tiles = <_Tile>[];
    for (final vs in states) {
      final isMe = vs.userId == myId;
      final display = participantDisplay(
        vs.userId,
        members: members,
        users: users,
        cdnUrl: cdnUrl,
        ensure: ensure,
      );
      // Follow LiveKit's tracks, not just the voice-state flags: a flag that
      // lags (or never arrives) used to hide a live camera or screen share.
      final VideoTrack? camera = session == null
          ? null
          : isMe
          ? session.localCameraTrack
          : session.remoteCameraTrack(vs.userId);
      tiles.add(
        _Tile(
          userId: vs.userId,
          name: display.name,
          avatarUrl: display.avatarUrl,
          bg: display.color,
          track: camera,
          isScreen: false,
          muted:
              vs.selfMute || vs.selfDeaf || vs.mute || vs.deaf || vs.suppress,
        ),
      );
      final VideoTrack? screen = session == null
          ? null
          : isMe
          ? session.localScreenTrack
          : session.remoteScreenTrack(vs.userId);
      if (screen != null || (vs.selfStream && session != null)) {
        tiles.add(
          _Tile(
            userId: vs.userId,
            name: display.name,
            avatarUrl: display.avatarUrl,
            bg: display.color,
            track: screen,
            isScreen: true,
            muted: false,
          ),
        );
      }
    }
    return tiles;
  }
}

/// One spotlighted tile filling the body above a horizontal strip of the
/// remaining tiles.
class _SpotlightLayout extends StatelessWidget {
  const _SpotlightLayout({
    required this.spotlight,
    required this.rest,
    required this.tileBuilder,
  });

  final _Tile spotlight;
  final List<_Tile> rest;
  final Widget Function(_Tile) tileBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: tileBuilder(spotlight),
          ),
        ),
        SizedBox(
          height: 110,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: HorizontalWheelScroll(
              builder: (context, controller) => ListView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (final t in rest)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: AspectRatio(aspectRatio: 1, child: tileBuilder(t)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The plain participant grid; the column count steps up with the tile count.
class _GridLayout extends StatelessWidget {
  const _GridLayout({required this.tiles, required this.tileBuilder});

  final List<_Tile> tiles;
  final Widget Function(_Tile) tileBuilder;

  @override
  Widget build(BuildContext context) {
    final columns = tiles.length <= 1
        ? 1
        : tiles.length <= 4
        ? 2
        : tiles.length <= 9
        ? 3
        : 4;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GridView.count(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 16 / 10,
        children: [for (final t in tiles) tileBuilder(t)],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    super.key,
    required this.tile,
    required this.speaking,
    required this.spotlighted,
    required this.onDoubleTap,
    this.onOpenVolume,
    this.fullScreen = false,
  });

  final bool fullScreen;
  final _Tile tile;
  final bool speaking;
  final bool spotlighted;
  final VoidCallback onDoubleTap;

  /// Opens the local volume menu (right-click position, null on long-press).
  /// Null for our own tiles.
  final void Function(Offset? position)? onOpenVolume;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final initial = accordInitial(tile.name);
    final openVolume = onOpenVolume;
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      onSecondaryTapUp: openVolume == null
          ? null
          : (d) => openVolume(d.globalPosition),
      onLongPress: openVolume == null ? null : () => openVolume(null),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.foreground,
          borderRadius: BorderRadius.circular(8),
          border: speaking
              ? Border.all(color: colors.green, width: 2)
              : spotlighted
              ? Border.all(color: colors.primary, width: 2)
              : null,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (tile.track != null)
              ValueListenableBuilder<int>(
                valueListenable: voiceFullScreenOpen,
                builder: (context, openFullScreen, _) =>
                    fullScreen || openFullScreen == 0
                    ? lk.VideoTrackRenderer(
                        tile.track!,
                        fit: tile.isScreen
                            ? lk.VideoViewFit.contain
                            : lk.VideoViewFit.cover,
                      )
                    : const Center(child: Icon(Icons.fullscreen, size: 32)),
              )
            else
              Center(
                child: AccordMemberAvatar(
                  avatarUrl: tile.avatarUrl,
                  initial: initial,
                  radius: 28,
                  backgroundColor: tile.bg,
                  initialStyle: const TextStyle(fontSize: 20),
                ),
              ),
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tile.muted) ...[
                      Icon(Icons.mic_off, size: 12, color: colors.red),
                      const SizedBox(width: 4),
                    ],
                    if (tile.isScreen) ...[
                      const Icon(
                        Icons.screen_share,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      tile.name,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The in-call control bar at the bottom of the voice view.
class _ControlBar extends ConsumerWidget {
  const _ControlBar({required this.channelId, required this.spaceId});

  final String channelId;
  final String? spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = BonfireThemeExtension.of(context);
    final voice = ref.watch(voiceControllerProvider);
    final notifier = ref.read(voiceControllerProvider.notifier);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final stage = watchIsStage(ref, spaceId, channelId);
    final myId = ref.watchUserId();
    final me = stage
        ? ref.watch(
            voiceStatesControllerProvider(
              serverKey,
            ).select((cache) => cache[channelId]?[myId]),
          )
        : null;
    final inAudience = stage && (me?.suppress ?? true);
    final stageAction = stage
        ? stageActionFor(
            me,
            moderator: watchVoiceModerationRights(ref, spaceId).mute,
          )
        : null;
    if (stage) {
      ref.listen(
        voiceStatesControllerProvider(
          serverKey,
        ).select((cache) => cache[channelId]?[myId]?.suppress),
        (prev, next) {
          if (prev == true && next == false) {
            showInfoSnack(context, 'You’re on stage — you can speak now.');
          }
        },
      );
    }
    final blockedReason = voice.speakBlockedReason;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.foreground,
        border: Border(top: BorderSide(color: colors.background, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ControlButton(
            icon: voice.selfMute || !voice.canSpeak ? Icons.mic_off : Icons.mic,
            tooltip: blockedReason ?? (voice.selfMute ? 'Unmute' : 'Mute'),
            active: voice.selfMute || !voice.canSpeak,
            activeColor: colors.red,
            onPressed: notifier.toggleMute,
          ),
          _ControlButton(
            icon: voice.selfDeaf || voice.serverDeaf
                ? Icons.headset_off
                : Icons.headset,
            tooltip: voice.serverDeaf
                ? 'A moderator has deafened you.'
                : (voice.selfDeaf ? 'Undeafen' : 'Deafen'),
            active: voice.selfDeaf || voice.serverDeaf,
            activeColor: colors.red,
            onPressed: notifier.toggleDeafen,
          ),
          if (stageAction != null && spaceId != null)
            _ControlButton(
              key: const Key('stage-action'),
              icon: switch (stageAction) {
                StageAction.raiseHand => Icons.back_hand_outlined,
                StageAction.lowerHand => Icons.back_hand,
                StageAction.speak => Icons.mic_external_on,
                StageAction.leaveStage => Icons.group,
              },
              tooltip: switch (stageAction) {
                StageAction.raiseHand => 'Raise hand to speak',
                StageAction.lowerHand => 'Lower hand',
                StageAction.speak => 'Speak on stage',
                StageAction.leaveStage => 'Move to audience',
              },
              active: stageAction == StageAction.lowerHand,
              activeColor: colors.primary,
              onPressed: () {
                final update = stageUpdateFor(stageAction);
                updateStage(
                  context,
                  ref,
                  serverKey: serverKey,
                  spaceId: spaceId!,
                  userId: '@me',
                  suppress: update.suppress,
                  requestToSpeak: update.requestToSpeak,
                );
              },
            ),
          if (!inAudience)
            _ControlButton(
              icon: voice.selfVideo ? Icons.videocam_off : Icons.videocam,
              tooltip: voice.selfVideo ? 'Stop camera' : 'Camera',
              active: voice.selfVideo,
              activeColor: colors.green,
              onPressed: notifier.toggleVideo,
            ),
          if (canShareScreen && !inAudience)
            _ControlButton(
              icon: voice.selfStream
                  ? Icons.stop_screen_share
                  : Icons.screen_share,
              tooltip: voice.selfStream ? 'Stop sharing' : 'Screen share',
              active: voice.selfStream,
              activeColor: colors.green,
              onPressed: () => toggleScreenShareWithPicker(context, ref),
            ),
          _ControlButton(
            icon: Icons.settings,
            tooltip: 'Voice settings',
            active: false,
            activeColor: colors.primary,
            onPressed: () => showVoiceSettings(context),
          ),
          _ControlButton(
            icon: Icons.call_end,
            tooltip: 'Disconnect',
            active: true,
            activeColor: colors.red,
            onPressed: () => unawaited(
              ref
                  .read(callControllerProvider.notifier)
                  .hangUp(channelId, spaceId),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.activeColor,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final Color activeColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: active ? activeColor : colors.darkGray,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(
            icon,
            size: 20,
            color: active ? Colors.white : colors.dirtyWhite,
          ),
        ),
      ),
    );
  }
}

/// The tile spotlighted when nobody picked one: someone else's screen share
/// first (what you came to watch), then your own.
int _defaultSpotlight(List<_Tile> tiles, String? myId) {
  final theirs = tiles.indexWhere((t) => t.isScreen && t.userId != myId);
  return theirs >= 0 ? theirs : tiles.indexWhere((t) => t.isScreen);
}
