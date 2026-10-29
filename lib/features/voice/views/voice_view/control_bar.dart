part of '../voice_view.dart';

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
