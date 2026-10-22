import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/components/settings_scaffold.dart';
import 'package:bonfire/shared/components/section_header.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:bonfire/features/voice/utils/audio_output_support.dart';
import 'package:bonfire/features/voice/views/mic_level_meter.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

/// Opens the Voice & Video settings page (input/output devices, volumes,
/// sensitivity + live mic test, camera).
Future<void> showVoiceSettings(BuildContext context) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const VoiceSettingsScreen()));
}

class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  List<MediaDevice> _audioInputs = const [];
  List<MediaDevice> _audioOutputs = const [];
  List<MediaDevice> _videoInputs = const [];
  bool _loadingDevices = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final inputs = await Hardware.instance.audioInputs();
      final outputs = await Hardware.instance.audioOutputs();
      final cameras = await Hardware.instance.videoInputs();
      if (!mounted) return;
      setState(() {
        _audioInputs = inputs;
        _audioOutputs = outputs;
        _videoInputs = cameras;
        _loadingDevices = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final connected = ref.watch(
      voiceControllerProvider.select((v) => v.isConnected),
    );

    return SettingsScaffold(
      title: 'Voice & Video',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            title: const Text('Relay-only voice'),
            subtitle: const Text(
              'Route voice, video and screen sharing through '
              'a TURN relay. Requires server support and may increase latency. '
              'Applies on your next connection; leave and rejoin to apply now.',
            ),
            value: settings.voiceRelayOnly,
            onChanged: controller.setVoiceRelayOnly,
          ),
          SectionHeader('Input device'),
          _DeviceDropdown(
            devices: _audioInputs,
            loading: _loadingDevices,
            selectedId: settings.audioInputDeviceId,
            fallbackLabel: 'Microphone',
            onChanged: controller.setAudioInputDevice,
          ),
          _PercentSlider(
            label: 'Input volume',
            value: settings.inputVolume,
            onChanged: controller.setInputVolume,
          ),
          SectionHeader('Input mode'),
          SwitchListTile(
            key: const Key('push-to-talk-switch'),
            title: const Text('Push to talk'),
            subtitle: Text(
              'Your mic only transmits while you hold the key (with the app '
              'focused) or the talk button in the voice bar.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.pushToTalk,
            onChanged: controller.setPushToTalk,
          ),
          ListTile(
            key: const Key('push-to-talk-key'),
            enabled: settings.pushToTalk,
            title: const Text('Push-to-talk key'),
            subtitle: Text(settings.pushToTalkKeyLabel),
            trailing: TextButton(
              onPressed: settings.pushToTalk
                  ? () async {
                      final key = await _captureKey(context);
                      if (key != null) {
                        controller.setPushToTalkKey(key.$1, key.$2);
                      }
                    }
                  : null,
              child: const Text('Change'),
            ),
          ),
          SectionHeader('Mic test'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MicLevelMeter(
                  height: 10,
                  threshold: settings.speakingThreshold,
                ),
                const SizedBox(height: 6),
                Text(
                  connected
                      ? 'Speak — the bar lights up green when you cross the '
                            'threshold (yellow marker).'
                      : 'Join a voice channel to test your microphone.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: colors.gray),
                ),
              ],
            ),
          ),
          _PercentSlider(
            label: 'Input sensitivity',
            value: settings.inputSensitivity,
            max: 100,
            onChanged: controller.setInputSensitivity,
          ),
          const Divider(height: 24),
          SectionHeader('Voice processing'),
          SwitchListTile(
            key: const Key('noise-suppression-switch'),
            title: const Text('Noise suppression'),
            subtitle: Text(
              'Filters background noise such as fans, keyboards and traffic.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.voiceNoiseSuppression,
            onChanged: controller.setVoiceNoiseSuppression,
          ),
          SwitchListTile(
            key: const Key('echo-cancellation-switch'),
            title: const Text('Echo cancellation'),
            subtitle: Text(
              'Stops others hearing themselves through your speakers.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.voiceEchoCancellation,
            onChanged: controller.setVoiceEchoCancellation,
          ),
          SwitchListTile(
            key: const Key('auto-gain-switch'),
            title: const Text('Automatic gain control'),
            subtitle: Text(
              'Keeps your voice at a steady level.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.voiceAutoGainControl,
            onChanged: controller.setVoiceAutoGainControl,
          ),
          SwitchListTile(
            key: const Key('high-quality-audio-switch'),
            title: const Text('High quality audio'),
            subtitle: Text(
              'Sends your microphone at 128 kbps — for music or instruments. '
              'Turn the three filters above off for the cleanest result. '
              'Applies when you next join a voice channel.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.voiceHighQualityAudio,
            onChanged: controller.setVoiceHighQualityAudio,
          ),
          const Divider(height: 24),
          if (canPickAudioOutputDevice) ...[
            SectionHeader('Output device'),
            _DeviceDropdown(
              key: const Key('audio-output-dropdown'),
              devices: _audioOutputs,
              loading: _loadingDevices,
              selectedId: settings.audioOutputDeviceId,
              fallbackLabel: 'Speaker',
              onChanged: controller.setAudioOutputDevice,
            ),
          ],
          _PercentSlider(
            label: 'Output volume',
            value: settings.outputVolume,
            onChanged: controller.setOutputVolume,
          ),
          const Divider(height: 24),
          SectionHeader('Away'),
          ListTile(
            title: const Text('Mark me away after'),
            subtitle: Text(
              'While in a voice channel, with no input, mic activity or window '
              'focus. Shown to other members as an idle status.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            trailing: DropdownButton<int>(
              key: const Key('afk-timeout-dropdown'),
              value:
                  afkTimeoutOptionsMinutes.contains(
                    settings.voiceAfkTimeoutMinutes,
                  )
                  ? settings.voiceAfkTimeoutMinutes
                  : defaultAfkTimeoutMinutes,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value != null) {
                  controller.setVoiceAfkTimeoutMinutes(value);
                }
              },
              items: [
                for (final minutes in afkTimeoutOptionsMinutes)
                  DropdownMenuItem(
                    value: minutes,
                    child: Text(afkTimeoutLabel(minutes)),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            key: const Key('afk-auto-move-switch'),
            title: const Text('Move me to the AFK channel'),
            subtitle: Text(
              "When the space has one set. You'll be moved back by rejoining "
              'the channel you want.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.voiceAfkAutoMove,
            onChanged: settings.voiceAfkTimeoutMinutes > 0
                ? controller.setVoiceAfkAutoMove
                : null,
          ),
          const Divider(height: 24),
          SectionHeader('Camera'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'Quality of your webcam when you turn on video.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          ),
          _DeviceDropdown(
            devices: _videoInputs,
            loading: _loadingDevices,
            selectedId: settings.videoInputDeviceId,
            fallbackLabel: 'Camera',
            onChanged: controller.setVideoInputDevice,
          ),
          ListTile(
            key: const Key('camera-resolution-dropdown'),
            title: const Text('Camera resolution'),
            trailing: DropdownButton<int>(
              value: settings.videoResolution,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value != null) controller.setVideoResolution(value);
              },
              items: [
                for (
                  var i = 0;
                  i < AccordSettings.videoResolutionLabels.length;
                  i++
                )
                  DropdownMenuItem(
                    value: i,
                    child: Text(AccordSettings.videoResolutionLabels[i]),
                  ),
              ],
            ),
          ),
          ListTile(
            key: const Key('camera-fps-dropdown'),
            title: const Text('Camera frame rate'),
            trailing: DropdownButton<int>(
              value: settings.videoFps,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value != null) controller.setVideoFps(value);
              },
              items: [
                for (final fps in AccordSettings.videoFpsOptions)
                  DropdownMenuItem(value: fps, child: Text('$fps fps')),
              ],
            ),
          ),
          const Divider(height: 24),
          SectionHeader('Screen share'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'Separate from the camera settings above — these apply when you '
              'share a screen or window.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
          ),
          ListTile(
            key: const Key('screen-share-resolution-dropdown'),
            title: const Text('Screen share resolution'),
            subtitle: Text(
              'Higher resolutions need more upload and CPU.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            trailing: DropdownButton<int>(
              value: settings.screenShareResolution,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value != null) controller.setScreenShareResolution(value);
              },
              items: [
                for (
                  var i = 0;
                  i < AccordSettings.screenShareResolutionLabels.length;
                  i++
                )
                  DropdownMenuItem(
                    value: i,
                    child: Text(AccordSettings.screenShareResolutionLabels[i]),
                  ),
              ],
            ),
          ),
          ListTile(
            key: const Key('screen-share-fps-dropdown'),
            title: const Text('Screen share frame rate'),
            subtitle: Text(
              '60 fps for games and video; 30 or 15 is plenty for slides.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            trailing: DropdownButton<int>(
              value: settings.screenShareFps,
              underline: const SizedBox.shrink(),
              onChanged: (value) {
                if (value != null) controller.setScreenShareFps(value);
              },
              items: [
                for (final fps in AccordSettings.screenShareFpsOptions)
                  DropdownMenuItem(value: fps, child: Text('$fps fps')),
              ],
            ),
          ),
          SwitchListTile(
            key: const Key('screen-share-audio-switch'),
            title: const Text('Share audio'),
            subtitle: Text(
              'Sends the sound of the shared tab or screen too. Works in '
              'Chrome and Edge on a computer; the desktop app shares video '
              'only for now.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.screenShareAudio,
            onChanged: controller.setScreenShareAudio,
          ),
          SwitchListTile(
            key: const Key('screen-share-motion-switch'),
            title: const Text('Prioritise smooth motion'),
            subtitle: Text(
              'Keeps the frame rate up on a slow connection by softening the '
              'picture. Turn off to keep text sharp instead.',
              style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
            ),
            value: settings.screenShareMotionPriority,
            onChanged: controller.setScreenShareMotionPriority,
          ),
        ],
      ),
    );
  }
}

/// Waits for the next key press and returns its physical USB HID usage and a
/// display label, or null when the dialog is dismissed.
Future<(int, String)?> _captureKey(BuildContext context) {
  return showDialog<(int, String)>(
    context: context,
    builder: (dialogContext) => Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.handled;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(dialogContext).pop();
          return KeyEventResult.handled;
        }
        Navigator.of(
          dialogContext,
        ).pop((event.physicalKey.usbHidUsage, pushToTalkKeyLabel(event)));
        return KeyEventResult.handled;
      },
      child: AlertDialog(
        title: const Text('Push-to-talk key'),
        content: const Text('Press the key to use. Esc cancels.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );
}

/// How a bound key is shown: the character it types on the current layout,
/// else the key's name (F-keys, Ctrl, Space…).
String pushToTalkKeyLabel(KeyEvent event) {
  final character = event.character?.trim() ?? '';
  if (character.isNotEmpty) return character.toUpperCase();
  return event.logicalKey.keyLabel.isNotEmpty
      ? event.logicalKey.keyLabel
      : 'Key ${event.physicalKey.usbHidUsage.toRadixString(16)}';
}

/// A device picker with a leading "System default" option (empty id).
class _DeviceDropdown extends StatelessWidget {
  const _DeviceDropdown({
    super.key,
    required this.devices,
    required this.loading,
    required this.selectedId,
    required this.fallbackLabel,
    required this.onChanged,
  });

  final List<MediaDevice> devices;
  final bool loading;
  final String selectedId;
  final String fallbackLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // Only offer the saved id if it still exists; otherwise fall back to
    // default so the dropdown has a valid value.
    final ids = devices.map((d) => d.deviceId).toSet();
    final value = ids.contains(selectedId) ? selectedId : '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        onChanged: loading ? null : (v) => onChanged(v ?? ''),
        items: [
          const DropdownMenuItem(value: '', child: Text('System default')),
          for (var i = 0; i < devices.length; i++)
            DropdownMenuItem(
              value: devices[i].deviceId,
              child: Text(
                devices[i].label.isNotEmpty
                    ? devices[i].label
                    : '$fallbackLabel ${i + 1}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// A labelled 0–[max]% slider showing the current percentage.
class _PercentSlider extends StatelessWidget {
  const _PercentSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.max = 200,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text('$value%')],
      ),
      subtitle: Slider(
        value: value.toDouble().clamp(0, max.toDouble()),
        max: max.toDouble(),
        divisions: max,
        onChanged: (v) => onChanged(v.round()),
      ),
    );
  }
}
