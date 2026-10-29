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
import 'package:flutter/services.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack;
import 'package:livekit_client/livekit_client.dart' as lk;

part 'voice_view/video_grid.dart';
part 'voice_view/control_bar.dart';

/// Presents the voice channel full-screen as its own route, rendering
/// [VoiceChannelView] in [VoiceChannelView.fullScreen] mode so its header
/// shows a "minimize" button that pops back.
/// Whether the voice view in the message pane fills the window. Full screen
/// happens in place — the home screen hides everything around the view —
/// rather than by pushing a second view: building a second set of video
/// renderers (and tearing one down) crashes the Flutter engine on Windows.
final voiceViewExpanded = ValueNotifier<bool>(false);

/// Expands the voice view to fill the window (and the screen, on desktop), or
/// restores it.
Future<void> setVoiceViewExpanded(bool expanded) async {
  if (voiceViewExpanded.value == expanded) return;
  voiceViewExpanded.value = expanded;
  // Esc leaves full screen wherever keyboard focus is.
  if (expanded) {
    HardwareKeyboard.instance.addHandler(_escapeExitsFullScreen);
  } else {
    HardwareKeyboard.instance.removeHandler(_escapeExitsFullScreen);
  }
  if (_hasDesktopWindow) {
    try {
      await windowManager.setFullScreen(expanded);
    } catch (e) {
      debugPrint('Voice full screen failed: $e');
    }
  }
}

bool _escapeExitsFullScreen(KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) {
    return false;
  }
  setVoiceViewExpanded(false);
  return true;
}

/// Phones share the whole screen, this app included, so our own share must
/// not be previewed there (it would film itself); desktops share a chosen
/// screen or window.
bool get screenShareCapturesApp =>
    !kIsWeb && (UniversalPlatform.isAndroid || UniversalPlatform.isIOS);

bool get _hasDesktopWindow =>
    !kIsWeb &&
    (UniversalPlatform.isWindows ||
        UniversalPlatform.isLinux ||
        UniversalPlatform.isMacOS);

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

  /// One global key per video tile of this view, so a tile moving between the
  /// grid and the spotlight is moved, not rebuilt: rebuilding tears down and
  /// recreates its video renderer, which crashes the engine on Windows.
  final _tileKeys = <String, GlobalKey>{};

  /// Whether the strip of other participants under the spotlighted tile is
  /// folded away (the chevron between them), so a stream can take the whole
  /// body in full screen.
  bool _stripHidden = false;

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
  void dispose() {
    // Leaving the voice view (another channel, another space) ends full
    // screen; scheduled because the home screen rebuilds on it.
    if (!widget.fullScreen && voiceViewExpanded.value) {
      Future.microtask(() => setVoiceViewExpanded(false));
    }
    super.dispose();
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
        ? ValueListenableBuilder<bool>(
            valueListenable: voiceViewExpanded,
            builder: (context, expanded, _) => _ConnectedBody(
              tileKeys: _tileKeys,
              channelId: widget.channelId,
              spaceId: widget.spaceId,
              fullScreen: widget.fullScreen,
              // Full screen: the video runs edge to edge, no gutter.
              edgeToEdge: expanded || widget.fullScreen,
              spotlightUserId: _spotlightUserId,
              onToggleSpotlight: (userId) => setState(
                () => _spotlightUserId = _spotlightUserId == userId
                    ? null
                    : userId,
              ),
              stripHidden: _stripHidden,
              onToggleStrip: () => setState(() => _stripHidden = !_stripHidden),
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
          if (widget.fullScreen || _isDmCall)
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
            )
          else
            ValueListenableBuilder<bool>(
              valueListenable: voiceViewExpanded,
              builder: (context, expanded, _) => IconButton(
                key: const Key('voice-full-screen'),
                tooltip: expanded ? 'Exit full screen (Esc)' : 'Full screen',
                onPressed: () => setVoiceViewExpanded(!expanded),
                icon: Icon(
                  expanded ? Icons.fullscreen_exit : Icons.fullscreen,
                  size: 20,
                  color: colors.dirtyWhite,
                ),
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
