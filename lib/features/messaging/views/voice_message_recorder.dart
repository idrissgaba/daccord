import 'dart:async';

import 'package:bonfire/features/messaging/utils/attachment_types.dart';
import 'package:bonfire/features/messaging/utils/voice_message.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart'
    show micPermissionDeniedMessage;
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:universal_io/io.dart';

/// Records a voice message in place of the composer's text field: a red dot,
/// the elapsed time, a live level bar, discard and send. Recording starts as
/// soon as the widget appears and stops (sending) at [maxVoiceMessageDuration].
///
/// [onRecorded] receives the finished recording as an attachment;
/// [onClosed] runs when the recorder goes away without one, with the reason
/// when that was a failure rather than the user discarding it.
class VoiceMessageRecorder extends StatefulWidget {
  const VoiceMessageRecorder({
    super.key,
    required this.onRecorded,
    required this.onClosed,
  });

  final ValueChanged<PendingAttachment> onRecorded;
  final void Function(String? error) onClosed;

  @override
  State<VoiceMessageRecorder> createState() => _VoiceMessageRecorderState();
}

class _VoiceMessageRecorderState extends State<VoiceMessageRecorder> {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitude;
  Timer? _ticker;
  DateTime? _startedAt;
  AudioEncoder? _encoder;
  Duration _elapsed = Duration.zero;
  double _level = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        _close(micPermissionDeniedMessage);
        return;
      }
      AudioEncoder? encoder;
      for (final candidate in voiceMessageEncoders) {
        if (await _recorder.isEncoderSupported(candidate)) {
          encoder = candidate;
          break;
        }
      }
      if (encoder == null) {
        _close('This device cannot record audio');
        return;
      }
      final startedAt = DateTime.now();
      // Browsers record into memory and hand back a blob URL; native
      // recorders need a file to write to.
      var path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path =
            '${dir.path}${Platform.pathSeparator}'
            '${voiceMessageFilename(startedAt, voiceMessageExtension(encoder, web: false))}';
      }
      await _recorder.start(
        RecordConfig(
          encoder: encoder,
          numChannels: 1,
          bitRate: 64000,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      if (_finished || !mounted) return;
      _encoder = encoder;
      _startedAt = startedAt;
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final elapsed = DateTime.now().difference(startedAt);
        if (elapsed >= maxVoiceMessageDuration) {
          unawaited(_send());
          return;
        }
        if (mounted) setState(() => _elapsed = elapsed);
      });
      _amplitude = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((a) {
            // dBFS: -60 dB (silence) .. 0 dB (full scale).
            final level = ((a.current + 60) / 60).clamp(0.0, 1.0).toDouble();
            if (mounted) setState(() => _level = level);
          });
      setState(() {});
    } catch (e) {
      _close('Could not start recording: $e');
    }
  }

  Future<void> _send() async {
    if (_finished || _encoder == null) return;
    _stopTimers();
    final encoder = _encoder!;
    final startedAt = _startedAt!;
    final elapsed = DateTime.now().difference(startedAt);
    try {
      final result = await _recorder.stop();
      _finished = true;
      if (elapsed < minVoiceMessageDuration) {
        await _discardResult(result);
        widget.onClosed('Voice message too short — record at least a second');
        return;
      }
      if (result == null || result.isEmpty) {
        widget.onClosed('Recording failed');
        return;
      }
      final bytes = await _readResult(result);
      widget.onRecorded(
        PendingAttachment.fromBytes(
          name: voiceMessageFilename(
            startedAt,
            voiceMessageExtension(encoder, web: kIsWeb),
          ),
          bytes: bytes,
        ),
      );
    } catch (e) {
      _finished = true;
      widget.onClosed('Recording failed: $e');
    }
  }

  Future<void> _discard() async {
    if (_finished) return;
    _stopTimers();
    _finished = true;
    try {
      await _recorder.cancel();
    } catch (_) {
      // Nothing was being recorded; discarding is still what the user wants.
    }
    widget.onClosed(null);
  }

  void _close(String error) {
    if (_finished) return;
    _finished = true;
    _stopTimers();
    widget.onClosed(error);
  }

  /// The recording's bytes: fetched from the blob URL on the web, read and
  /// deleted from the temporary file elsewhere.
  Future<Uint8List> _readResult(String result) async {
    if (kIsWeb) {
      final response = await http.get(Uri.parse(result));
      return response.bodyBytes;
    }
    final file = File(result);
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }

  Future<void> _discardResult(String? result) async {
    if (kIsWeb || result == null || result.isEmpty) return;
    try {
      await File(result).delete();
    } catch (_) {
      // Already gone.
    }
  }

  void _stopTimers() {
    _ticker?.cancel();
    _ticker = null;
    unawaited(_amplitude?.cancel());
    _amplitude = null;
  }

  @override
  void dispose() {
    _stopTimers();
    if (!_finished) {
      _finished = true;
      unawaited(_recorder.cancel().catchError((_) {}));
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final recording = _startedAt != null && !_finished;
    return Row(
      key: const Key('voice-message-recorder'),
      children: [
        IconButton(
          key: const Key('voice-message-discard'),
          tooltip: 'Discard',
          onPressed: _finished ? null : _discard,
          icon: Icon(Icons.delete_outline, size: 20, color: colors.red),
        ),
        Icon(
          Icons.fiber_manual_record,
          size: 12,
          color: recording ? colors.red : colors.gray,
        ),
        const SizedBox(width: 6),
        Text(
          recording ? formatRecordingDuration(_elapsed) : 'Starting…',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: recording ? _level : 0,
              minHeight: 4,
              backgroundColor: colors.gray.withValues(alpha: 0.3),
              color: colors.green,
            ),
          ),
        ),
        IconButton(
          key: const Key('voice-message-send'),
          tooltip: 'Send voice message',
          onPressed: recording ? _send : null,
          icon: Icon(Icons.send, size: 20, color: colors.dirtyWhite),
        ),
      ],
    );
  }
}
