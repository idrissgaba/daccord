import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/services/voice_session.dart'
    show VoiceSessionState;
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('voiceGain', () {
    test('100% is unity, 0% is silent, 200% is double', () {
      expect(voiceGain(100), 1.0);
      expect(voiceGain(0), 0.0);
      expect(voiceGain(200), 2.0);
      expect(voiceGain(50), 0.5);
    });

    test('clamps out-of-range input to 0.0–2.0', () {
      expect(voiceGain(300), 2.0);
      expect(voiceGain(-50), 0.0);
    });
  });

  group('VoiceAudioOptions', () {
    test('defaults keep every platform filter on at the standard bitrate', () {
      const audio = VoiceAudioOptions();
      final capture = audio.captureOptions(null);
      expect(capture.noiseSuppression, isTrue);
      expect(capture.echoCancellation, isTrue);
      expect(capture.autoGainControl, isTrue);
      expect(capture.voiceIsolation, isTrue);
      expect(audio.publishOptions.encoding?.maxBitrate, 64000);
      expect(audio.publishOptions.red, isTrue);
      expect(audio.publishOptions.dtx, isTrue);
    });

    test('turning noise suppression off also drops voice isolation', () {
      const audio = VoiceAudioOptions(noiseSuppression: false);
      final capture = audio.captureOptions('mic-1');
      expect(capture.noiseSuppression, isFalse);
      expect(capture.voiceIsolation, isFalse);
      expect(capture.deviceId, 'mic-1');
    });

    test('high quality raises the bitrate and disables DTX', () {
      const audio = VoiceAudioOptions(highQuality: true);
      expect(audio.publishOptions.encoding?.maxBitrate, 128000);
      expect(audio.publishOptions.dtx, isFalse);
    });

    test('maps from settings and compares by value', () {
      const settings = AccordSettings(
        voiceEchoCancellation: false,
        voiceHighQualityAudio: true,
      );
      expect(
        voiceAudioOptionsOf(settings),
        const VoiceAudioOptions(echoCancellation: false, highQuality: true),
      );
      expect(
        voiceAudioOptionsOf(const AccordSettings()),
        const VoiceAudioOptions(),
      );
    });
  });

  group('normalizeDeviceId', () {
    test('empty / null becomes null (system default)', () {
      expect(normalizeDeviceId(null), isNull);
      expect(normalizeDeviceId(''), isNull);
    });

    test('a real id passes through', () {
      expect(normalizeDeviceId('mic-1'), 'mic-1');
    });
  });

  group('shouldAutoReconnect', () {
    test('reconnects on an unintentional drop while connected, once', () {
      expect(
        shouldAutoReconnect(
          intentional: false,
          stillConnected: true,
          alreadyAttempted: false,
        ),
        isTrue,
      );
    });

    test('does not reconnect when the drop was intentional', () {
      expect(
        shouldAutoReconnect(
          intentional: true,
          stillConnected: true,
          alreadyAttempted: false,
        ),
        isFalse,
      );
    });

    test('does not reconnect twice for the same drop', () {
      expect(
        shouldAutoReconnect(
          intentional: false,
          stillConnected: true,
          alreadyAttempted: true,
        ),
        isFalse,
      );
    });

    test('does not reconnect when no longer connected', () {
      expect(
        shouldAutoReconnect(
          intentional: false,
          stillConnected: false,
          alreadyAttempted: false,
        ),
        isFalse,
      );
    });
  });

  group('needsReconnect', () {
    test('true for dropped/failed/reconnecting, false for healthy', () {
      expect(needsReconnect(VoiceSessionState.disconnected), isTrue);
      expect(needsReconnect(VoiceSessionState.failed), isTrue);
      expect(needsReconnect(VoiceSessionState.reconnecting), isTrue);
      expect(needsReconnect(VoiceSessionState.connected), isFalse);
      expect(needsReconnect(VoiceSessionState.connecting), isFalse);
    });
  });

  group('isVoiceDoubleTap', () {
    final now = DateTime(2026, 1, 1, 12);

    test('a first click on a row is never a join', () {
      expect(isVoiceDoubleTap(null, now), isFalse);
    });

    test('a second click inside the window joins', () {
      expect(
        isVoiceDoubleTap(now.subtract(const Duration(milliseconds: 150)), now),
        isTrue,
      );
      expect(isVoiceDoubleTap(now.subtract(voiceDoubleTapWindow), now), isTrue);
    });

    test('a slow second click only re-selects', () {
      expect(
        isVoiceDoubleTap(
          now.subtract(voiceDoubleTapWindow + const Duration(milliseconds: 1)),
          now,
        ),
        isFalse,
      );
      expect(
        isVoiceDoubleTap(now.subtract(const Duration(seconds: 5)), now),
        isFalse,
      );
    });

    test('ignores a clock that jumped backwards', () {
      expect(
        isVoiceDoubleTap(now.add(const Duration(milliseconds: 100)), now),
        isFalse,
      );
    });
  });

  group('isMicPermissionError', () {
    test('recognises each platform\'s denial', () {
      // iOS / web: flutter_webrtc wraps the DOMException name in a string.
      expect(
        isMicPermissionError('Unable to getUserMedia: NotAllowedError'),
        isTrue,
      );
      // Android: GetUserMediaImpl's message.
      expect(isMicPermissionError(Exception('PermissionDenied')), isTrue);
      expect(
        isMicPermissionError('Unable to getUserMedia: permission denied'),
        isTrue,
      );
    });

    test('a device/transport failure is not a permission failure', () {
      expect(
        isMicPermissionError('Unable to getUserMedia: NotFoundError'),
        isFalse,
      );
      expect(
        isMicPermissionError(
          'LiveKit Exception: [TrackPublishException] Failed to publish track',
        ),
        isFalse,
      );
    });
  });

  group('describeMicFailure', () {
    test('a denied mic gets the actionable Settings hint', () {
      expect(
        describeMicFailure('Unable to getUserMedia: NotAllowedError'),
        micPermissionDeniedMessage,
      );
      expect(micPermissionDeniedMessage, contains('Settings'));
    });

    test('any other failure keeps the platform reason', () {
      expect(
        describeMicFailure('Unable to getUserMedia: NotFoundError'),
        'Microphone unavailable: NotFoundError',
      );
    });

    test('an empty reason still reads as a mic failure', () {
      expect(describeMicFailure(''), 'Microphone unavailable');
    });
  });
}
