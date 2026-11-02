import 'package:bonfire/features/voice/utils/voice_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('summarizeVoiceStream', () {
    test('bitrate comes from the byte delta over the interval', () {
      const a = VoiceStreamSample(timestampMs: 1000, bytes: 10000, packets: 50);
      const b = VoiceStreamSample(
        timestampMs: 3000,
        bytes: 34000,
        packets: 150,
      );
      // 24 000 bytes in 2 s = 96 kbps.
      expect(summarizeVoiceStream(b, previous: a).kbps, closeTo(96, 0.01));
      expect(summarizeVoiceStream(b).kbps, 0);
    });

    test('loss is lost over lost plus delivered', () {
      const s = VoiceStreamSample(
        timestampMs: 1,
        bytes: 1,
        packets: 95,
        packetsLost: 5,
      );
      expect(summarizeVoiceStream(s).lossPercent, closeTo(5, 0.001));
      expect(
        summarizeVoiceStream(
          const VoiceStreamSample(timestampMs: 1, bytes: 1, packets: 10),
        ).lossPercent,
        isNull,
      );
    });

    test('jitter, RTT and concealment convert to ms and percent', () {
      const s = VoiceStreamSample(
        timestampMs: 1,
        bytes: 1,
        packets: 1,
        jitterSeconds: 0.012,
        roundTripSeconds: 0.045,
        concealedSamples: 4800,
        totalSamplesDuration: 10, // 10 s at 48 kHz = 480 000 samples
        clockRate: 48000,
        codec: 'audio/opus',
        channels: 1,
      );
      final sum = summarizeVoiceStream(s);
      expect(sum.jitterMs, closeTo(12, 0.001));
      expect(sum.roundTripMs, closeTo(45, 0.001));
      expect(sum.concealedPercent, closeTo(1, 0.001));
      expect(sum.codecLabel, 'Opus 48 kHz mono');
    });
  });

  group('gradeVoiceStream', () {
    VoiceStreamSummary s(double? loss, double? concealed) => VoiceStreamSummary(
      kbps: 64,
      lossPercent: loss,
      concealedPercent: concealed,
    );
    test('grades on the worse of loss and concealment', () {
      expect(gradeVoiceStream(s(0.2, 0.5)), VoiceLinkGrade.good);
      expect(gradeVoiceStream(s(2, 0)), VoiceLinkGrade.fair);
      expect(gradeVoiceStream(s(0, 7)), VoiceLinkGrade.poor);
      expect(gradeVoiceStream(s(null, null)), VoiceLinkGrade.good);
    });
  });

  test('codecLabel handles missing parts', () {
    expect(codecLabel(null), isNull);
    expect(codecLabel('audio/opus'), 'Opus');
    expect(
      codecLabel('audio/opus', clockRate: 48000, channels: 2),
      'Opus 48 kHz stereo',
    );
  });
}
