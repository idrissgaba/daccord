part of '../voice_view.dart';

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
    this.watching = true,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
  final Color bg;
  final VideoTrack? track;
  final bool isScreen;
  final bool muted;

  /// False for a peer's screen share we haven't chosen to watch: the tile
  /// offers a "Watch stream" button instead of the video.
  final bool watching;

  /// Which tile is spotlighted: a person has a camera tile and, while
  /// sharing, a screen tile — by user id alone the camera tile won, so
  /// opening someone's screen share showed their avatar instead.
  String get spotlightKey => '$userId:${isScreen ? 'screen' : 'camera'}';
}

/// The in-call body: the video grid (or spotlight + strip).
class _ConnectedBody extends ConsumerWidget {
  const _ConnectedBody({
    required this.tileKeys,
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

  /// The owning view's tile keys (see `_VoiceChannelViewState._tileKeys`).
  final Map<String, GlobalKey> tileKeys;

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
                    tileKeys: tileKeys,
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
    final voice = ref.read(voiceControllerProvider.notifier);
    Widget tileWidget(_Tile t) => _VideoTile(
      key: tileKeys.putIfAbsent(t.spotlightKey, GlobalKey.new),
      fullScreen: fullScreen,
      tile: t,
      speaking: speaking.contains(t.userId),
      spotlighted: spotlightUserId == t.spotlightKey,
      onDoubleTap: () => onToggleSpotlight(t.spotlightKey),
      onToggleWatch: !t.isScreen || t.userId == myId
          ? null
          : () {
              // Stopping also drops the stream's spotlight: an unwatched
              // tile is only a "live" card and shouldn't fill the body.
              if (t.watching && spotlightUserId == t.spotlightKey) {
                onToggleSpotlight(t.spotlightKey);
              }
              voice.setWatchingStream(t.userId, !t.watching);
            },
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
      // A peer's share stays unsubscribed until we watch it, so the tile
      // follows the publication (and the voice-state flag), not the track.
      final streaming =
          screen != null ||
          (session != null &&
              (vs.selfStream ||
                  (!isMe && session.remoteIsStreaming(vs.userId))));
      if (streaming) {
        tiles.add(
          _Tile(
            userId: vs.userId,
            name: display.name,
            avatarUrl: display.avatarUrl,
            bg: display.color,
            track: screen,
            isScreen: true,
            muted: false,
            watching: isMe || session!.isWatchingStream(vs.userId),
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
    this.onToggleWatch,
    this.fullScreen = false,
  });

  final bool fullScreen;
  final _Tile tile;
  final bool speaking;
  final bool spotlighted;
  final VoidCallback onDoubleTap;

  /// Starts or stops watching this peer's stream. Null for anything but a
  /// peer's screen tile.
  final VoidCallback? onToggleWatch;

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
            if (tile.isScreen && !tile.watching)
              _LiveCard(tile: tile, onWatch: onToggleWatch)
            else if (tile.track != null)
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
            if (tile.isScreen && tile.watching && onToggleWatch != null)
              Positioned(
                right: 6,
                top: 6,
                child: _TileButton(
                  key: Key('stop-watching-${tile.userId}'),
                  label: 'Stop watching',
                  icon: Icons.visibility_off,
                  onPressed: onToggleWatch!,
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

/// A peer's screen share we aren't receiving: their avatar, a LIVE badge and
/// the button that starts the stream, as in other chat apps.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.tile, required this.onWatch});

  final _Tile tile;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AccordMemberAvatar(
          avatarUrl: tile.avatarUrl,
          initial: accordInitial(tile.name),
          radius: 24,
          backgroundColor: tile.bg,
          initialStyle: const TextStyle(fontSize: 18),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: colors.red,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _TileButton(
          key: Key('watch-stream-${tile.userId}'),
          label: 'Watch stream',
          icon: Icons.play_arrow,
          onPressed: onWatch,
          primary: true,
        ),
      ],
    );
  }
}

/// A compact pill button drawn over a video tile.
class _TileButton extends StatelessWidget {
  const _TileButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return FilledButton.icon(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: primary ? colors.primary : Colors.black54,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

/// The tile spotlighted when nobody picked one: someone else's screen share
/// first (what you came to watch), then your own.
int _defaultSpotlight(List<_Tile> tiles, String? myId) {
  // Only a stream we watch fills the body; a live card stays in the grid.
  final theirs = tiles.indexWhere(
    (t) => t.isScreen && t.userId != myId && t.watching,
  );
  return theirs >= 0 ? theirs : tiles.indexWhere((t) => t.isScreen);
}
