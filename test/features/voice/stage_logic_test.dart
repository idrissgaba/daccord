import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/voice/utils/stage_logic.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:flutter_test/flutter_test.dart';

AccordVoiceState _vs(String userId, {bool suppress = true, String? hand}) =>
    AccordVoiceState(
      userId: userId,
      suppress: suppress,
      requestToSpeakTimestamp: hand,
    );

void main() {
  test('stages are voice channels', () {
    expect(isVoiceChannelType('voice'), isTrue);
    expect(isVoiceChannelType('stage'), isTrue);
    expect(isVoiceChannelType('text'), isFalse);
    expect(isVoiceChannelType(null), isFalse);
  });

  test('speakers and the audience, raised hands first by wait', () {
    final states = [
      _vs('quiet'),
      _vs('late', hand: '2026-10-24T10:05:00+00:00'),
      _vs('speaker', suppress: false),
      _vs('early', hand: '2026-10-24T10:00:00+00:00'),
      _vs('also-quiet'),
    ];
    expect(stageSpeakers(states).map((s) => s.userId), ['speaker']);
    expect(stageAudience(states).map((s) => s.userId), [
      'early',
      'late',
      'quiet',
      'also-quiet',
    ]);
  });

  test('the stage button follows who you are on stage', () {
    expect(stageActionFor(_vs('me'), moderator: false), StageAction.raiseHand);
    expect(
      stageActionFor(_vs('me', hand: 'x'), moderator: false),
      StageAction.lowerHand,
    );
    expect(stageActionFor(_vs('me'), moderator: true), StageAction.speak);
    expect(
      stageActionFor(_vs('me', suppress: false), moderator: true),
      StageAction.leaveStage,
    );
    expect(stageUpdateFor(StageAction.raiseHand), (
      suppress: null,
      requestToSpeak: true,
    ));
    expect(stageUpdateFor(StageAction.leaveStage), (
      suppress: true,
      requestToSpeak: null,
    ));
  });

  test('a raised hand round-trips and is absent when unset', () {
    final vs = AccordVoiceState.fromJson({
      'user_id': 'u',
      'session_id': 's',
      'suppress': true,
      'request_to_speak_timestamp': '2026-10-24T10:00:00+00:00',
    });
    expect(vs.requestToSpeakTimestamp, '2026-10-24T10:00:00+00:00');
    expect(vs.toJson()['request_to_speak_timestamp'], isNotNull);
    expect(
      AccordVoiceState(
        userId: 'u',
      ).toJson().containsKey('request_to_speak_timestamp'),
      isFalse,
    );
  });

  test('the audience is told to raise a hand, not that it lacks the right', () {
    expect(
      voiceSpeakBlockedReason(
        serverMute: false,
        serverDeaf: false,
        suppressed: true,
        stage: true,
      ),
      stageAudienceReason,
    );
    expect(
      voiceSpeakBlockedReason(
        serverMute: true,
        serverDeaf: false,
        suppressed: true,
        stage: true,
      ),
      'A moderator has muted you.',
    );
  });
}
