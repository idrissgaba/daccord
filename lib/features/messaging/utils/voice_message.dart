/// Voice messages: short mic recordings sent as an ordinary audio attachment
/// and recognised again on display by their file name, so servers and other
/// clients need nothing new to carry them.
library;

import 'package:record/record.dart' show AudioEncoder;

/// Longest voice message; recording stops and sends on its own at this point.
const Duration maxVoiceMessageDuration = Duration(minutes: 10);

/// Shorter recordings are treated as an accidental tap and discarded.
const Duration minVoiceMessageDuration = Duration(seconds: 1);

/// Encoders to try, best first: AAC in MP4 plays everywhere (Windows, Safari,
/// Android, Chrome), Opus in WebM is Firefox's compressed option, WAV is the
/// uncompressed last resort.
const List<AudioEncoder> voiceMessageEncoders = [
  AudioEncoder.aacLc,
  AudioEncoder.opus,
  AudioEncoder.wav,
];

/// The file extension of a recording made with [encoder]. Browsers wrap Opus
/// in WebM; native recorders use Ogg.
String voiceMessageExtension(AudioEncoder encoder, {required bool web}) =>
    switch (encoder) {
      AudioEncoder.aacLc => 'm4a',
      AudioEncoder.opus => web ? 'webm' : 'ogg',
      _ => 'wav',
    };

final RegExp _voiceMessageName = RegExp(
  r'^voice-message-\d{8}-\d{6}\.(m4a|webm|ogg|wav)$',
);

/// `voice-message-YYYYMMDD-HHMMSS.<extension>`, from the recording's start.
String voiceMessageFilename(DateTime startedAt, String extension) {
  String two(int v) => v.toString().padLeft(2, '0');
  final date =
      '${startedAt.year.toString().padLeft(4, '0')}'
      '${two(startedAt.month)}${two(startedAt.day)}';
  final time =
      '${two(startedAt.hour)}${two(startedAt.minute)}${two(startedAt.second)}';
  return 'voice-message-$date-$time.$extension';
}

/// Whether [filename] was produced by [voiceMessageFilename].
bool isVoiceMessageFilename(String filename) =>
    _voiceMessageName.hasMatch(filename);

/// `m:ss` for the recording timer.
String formatRecordingDuration(Duration elapsed) {
  final minutes = elapsed.inMinutes;
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
