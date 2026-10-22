import 'package:bonfire/features/messaging/utils/voice_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart' show AudioEncoder;

void main() {
  group('voice message file names', () {
    test('are stamped with the recording start and recognised again', () {
      final name = voiceMessageFilename(DateTime(2026, 10, 22, 9, 5, 7), 'm4a');
      expect(name, 'voice-message-20261022-090507.m4a');
      expect(isVoiceMessageFilename(name), isTrue);
    });

    test('ordinary audio files are not voice messages', () {
      expect(isVoiceMessageFilename('song.mp3'), isFalse);
      expect(isVoiceMessageFilename('voice-message.m4a'), isFalse);
      expect(
        isVoiceMessageFilename('voice-message-20261022-090507.mp3'),
        isFalse,
      );
    });
  });

  group('voiceMessageExtension', () {
    test('AAC records to m4a everywhere', () {
      expect(voiceMessageExtension(AudioEncoder.aacLc, web: true), 'm4a');
      expect(voiceMessageExtension(AudioEncoder.aacLc, web: false), 'm4a');
    });

    test('Opus is WebM in browsers and Ogg natively', () {
      expect(voiceMessageExtension(AudioEncoder.opus, web: true), 'webm');
      expect(voiceMessageExtension(AudioEncoder.opus, web: false), 'ogg');
    });

    test('anything else falls back to WAV', () {
      expect(voiceMessageExtension(AudioEncoder.wav, web: true), 'wav');
    });

    test('AAC is preferred over Opus and WAV', () {
      expect(voiceMessageEncoders.first, AudioEncoder.aacLc);
      expect(voiceMessageEncoders.last, AudioEncoder.wav);
    });
  });

  test('formatRecordingDuration shows minutes and padded seconds', () {
    expect(formatRecordingDuration(Duration.zero), '0:00');
    expect(formatRecordingDuration(const Duration(seconds: 9)), '0:09');
    expect(
      formatRecordingDuration(const Duration(minutes: 9, seconds: 59)),
      '9:59',
    );
  });

  test('limits are a second to ten minutes', () {
    expect(minVoiceMessageDuration, const Duration(seconds: 1));
    expect(maxVoiceMessageDuration, const Duration(minutes: 10));
  });
}
