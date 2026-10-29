import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:bonfire/features/voice/views/voice_moderation_menu.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Highest per-user volume the slider offers here. The web plays remote audio
/// through an `HTMLAudioElement`, which cannot amplify past 100 %.
int get maxUserVolumeSlider => kIsWeb ? 100 : AccordSettings.maxUserVolume;

/// Opens the local "User Volume" controls for [userId] on [serverKey]: an
/// anchored menu at [globalPosition] on desktop layouts (right-click), a bottom
/// sheet otherwise (long-press). Changes apply live and only affect what we
/// hear.
///
/// With [spaceId] and [channelId] (a space voice channel), the menu also
/// carries the voice moderation actions the current user may take. Without
/// [showVolume] (our own row) it carries only those. With [stream] (a screen
/// share tile) the slider sets their stream's volume instead of their voice.
Future<void> showUserVolumeMenu(
  BuildContext context, {
  required String serverKey,
  required String userId,
  required String name,
  Offset? globalPosition,
  String? spaceId,
  String? channelId,
  bool showVolume = true,
  bool stream = false,
}) {
  final moderation = spaceId != null && channelId != null;
  final panel = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showVolume)
        UserVolumePanel(
          serverKey: serverKey,
          userId: userId,
          name: name,
          stream: stream,
        )
      else
        ListTile(
          dense: true,
          title: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      if (moderation)
        VoiceModerationPanel(
          serverKey: serverKey,
          spaceId: spaceId,
          channelId: channelId,
          userId: userId,
        ),
    ],
  );
  if (shouldUseDesktopLayout(context) && globalPosition != null) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return Future.value();
    return showMenu<int>(
      context: context,
      color: BonfireThemeExtension.of(context).foreground,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        _PanelMenuEntry(
          height: (showVolume ? 200 : 48) + (moderation ? 200 : 0),
          child: panel,
        ),
      ],
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SafeArea(child: SingleChildScrollView(child: panel)),
  );
}

/// Hosts the interactive [UserVolumePanel] inside a popup menu, which
/// otherwise only offers selectable rows.
class _PanelMenuEntry extends PopupMenuEntry<int> {
  const _PanelMenuEntry({required this.height, required this.child});

  final Widget child;

  @override
  final double height;

  @override
  bool represents(int? value) => false;

  @override
  State<_PanelMenuEntry> createState() => _PanelMenuEntryState();
}

class _PanelMenuEntryState extends State<_PanelMenuEntry> {
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 280, child: widget.child);
}

/// Slider, "Mute for me" and reset for one participant's local volume.
class UserVolumePanel extends ConsumerWidget {
  const UserVolumePanel({
    super.key,
    required this.serverKey,
    required this.userId,
    required this.name,
    this.stream = false,
  });

  final String serverKey;
  final String userId;
  final String name;

  /// Sets the volume of their screen-share audio rather than their voice.
  final bool stream;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = stream ? streamVolumeId(userId) : userId;
    final volume = ref.watch(
      settingsControllerProvider.select((s) => s.userVolume(serverKey, id)),
    );
    final muted = ref.watch(
      settingsControllerProvider.select(
        (s) => s.isUserLocallyMuted(serverKey, id),
      ),
    );
    final controller = ref.read(settingsControllerProvider.notifier);
    final max = maxUserVolumeSlider;
    final shown = volume.clamp(0, max);
    final isDefault = volume == AccordSettings.defaultUserVolume && !muted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            title: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          ListTile(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(stream ? 'Stream Volume' : 'User Volume'),
                Text(muted ? 'Muted' : '$shown%'),
              ],
            ),
            subtitle: Slider(
              key: Key(stream ? 'stream-volume-slider' : 'user-volume-slider'),
              value: shown.toDouble(),
              max: max.toDouble(),
              divisions: max,
              label: '$shown%',
              onChanged: muted
                  ? null
                  : (v) =>
                        controller.setUserVolume(serverKey, id, v.round()),
            ),
          ),
          CheckboxListTile(
            dense: true,
            title: Text(stream ? 'Mute stream' : 'Mute for me'),
            value: muted,
            onChanged: (v) =>
                controller.setUserLocallyMuted(serverKey, id, v ?? false),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: isDefault
                    ? null
                    : () => controller.resetUserVolume(serverKey, id),
                child: const Text('Reset'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
