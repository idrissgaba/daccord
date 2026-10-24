import 'package:accordkit/accordkit.dart';

/// Channel types members join by voice: voice channels and stages.
bool isVoiceChannelType(String? type) => type == 'voice' || type == 'stage';

/// Why an audience member can't speak.
const stageAudienceReason =
    "You're in the audience. Raise your hand to ask to speak.";

/// A stage's speakers: everyone who has been brought up.
List<AccordVoiceState> stageSpeakers(Iterable<AccordVoiceState> states) => [
  for (final s in states)
    if (!s.suppress) s,
];

/// A stage's audience: raised hands first, longest-waiting first, then
/// everyone else in the order given.
List<AccordVoiceState> stageAudience(Iterable<AccordVoiceState> states) {
  final audience = [
    for (final s in states)
      if (s.suppress) s,
  ];
  final raised =
      [
        for (final s in audience)
          if (s.requestToSpeakTimestamp != null) s,
      ]..sort(
        (a, b) =>
            a.requestToSpeakTimestamp!.compareTo(b.requestToSpeakTimestamp!),
      );
  return [
    ...raised,
    for (final s in audience)
      if (s.requestToSpeakTimestamp == null) s,
  ];
}

/// What the current user's stage button does, from their voice state.
enum StageAction {
  /// In the audience: raise a hand.
  raiseHand,

  /// In the audience with a raised hand: lower it.
  lowerHand,

  /// A stage moderator in the audience: step up without asking.
  speak,

  /// A speaker: go back to the audience.
  leaveStage,
}

StageAction stageActionFor(AccordVoiceState? me, {required bool moderator}) {
  if (me != null && !me.suppress) return StageAction.leaveStage;
  if (moderator) return StageAction.speak;
  return me?.requestToSpeakTimestamp != null
      ? StageAction.lowerHand
      : StageAction.raiseHand;
}

/// The stage update request body for [action] (see `VoiceApi.updateStage`).
({bool? suppress, bool? requestToSpeak}) stageUpdateFor(StageAction action) =>
    switch (action) {
      StageAction.raiseHand => (suppress: null, requestToSpeak: true),
      StageAction.lowerHand => (suppress: null, requestToSpeak: false),
      StageAction.speak => (suppress: false, requestToSpeak: null),
      StageAction.leaveStage => (suppress: true, requestToSpeak: null),
    };
