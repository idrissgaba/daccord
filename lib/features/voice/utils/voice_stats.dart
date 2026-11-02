/// Pure summaries of the voice link's health, computed from two consecutive
/// WebRTC stats samples. Fed by `VoiceSession.collectStats` and shown in the
/// voice bar's connection-info panel, so a muffled or choppy call can be told
/// apart from a bad network.
library;

/// One raw sample of an RTP stream (ours going out, or a participant's coming
/// in), as WebRTC counts it: cumulative totals plus the sample time.
class VoiceStreamSample {
  const VoiceStreamSample({
    required this.timestampMs,
    required this.bytes,
    required this.packets,
    this.packetsLost,
    this.jitterSeconds,
    this.roundTripSeconds,
    this.concealedSamples,
    this.totalSamplesDuration,
    this.codec,
    this.channels,
    this.clockRate,
  });

  /// Sample time in milliseconds (WebRTC `timestamp`).
  final num timestampMs;

  /// Cumulative bytes sent or received.
  final num bytes;

  /// Cumulative packets sent or received.
  final num packets;

  /// Cumulative packets lost, when the stream reports it.
  final num? packetsLost;

  /// Inter-arrival jitter, in seconds.
  final num? jitterSeconds;

  /// Round-trip time to the server, in seconds (senders only).
  final num? roundTripSeconds;

  /// Samples the decoder had to invent to cover gaps (receivers only).
  final num? concealedSamples;

  /// Total audio duration played out so far, in seconds (receivers only).
  final num? totalSamplesDuration;

  final String? codec;
  final num? channels;
  final num? clockRate;
}

/// Everything the panel needs from one poll: our outgoing microphone stream,
/// each participant's incoming audio keyed by their user ID, and the server's
/// view of our link quality (`excellent`, `good`, `poor`, `lost`, `unknown`).
class VoiceLinkSnapshot {
  const VoiceLinkSnapshot({
    this.outgoing,
    this.incoming = const {},
    this.quality = 'unknown',
  });

  final VoiceStreamSample? outgoing;
  final Map<String, VoiceStreamSample> incoming;
  final String quality;
}

/// What the panel shows for one stream, derived from the newest and previous
/// sample. Null fields mean the stream didn't report that counter.
class VoiceStreamSummary {
  const VoiceStreamSummary({
    required this.kbps,
    required this.lossPercent,
    this.jitterMs,
    this.roundTripMs,
    this.concealedPercent,
    this.codecLabel,
  });

  /// Bitrate over the last interval, in kilobits per second.
  final double kbps;

  /// Share of packets lost over the whole stream so far, 0–100.
  final double? lossPercent;

  /// Jitter in milliseconds.
  final double? jitterMs;

  /// Round-trip time in milliseconds.
  final double? roundTripMs;

  /// Share of played audio the decoder had to conceal, 0–100 (receivers).
  final double? concealedPercent;

  /// e.g. `Opus 48 kHz mono`.
  final String? codecLabel;
}

/// Summarizes [current] against [previous] (null on the first sample, which
/// then reports 0 kbps).
VoiceStreamSummary summarizeVoiceStream(
  VoiceStreamSample current, {
  VoiceStreamSample? previous,
}) {
  var kbps = 0.0;
  if (previous != null && current.timestampMs > previous.timestampMs) {
    final seconds = (current.timestampMs - previous.timestampMs) / 1000;
    final bytes = current.bytes - previous.bytes;
    if (bytes > 0) kbps = bytes * 8 / 1000 / seconds;
  }
  double? loss;
  final lost = current.packetsLost;
  if (lost != null) {
    final total = current.packets + lost;
    loss = total > 0 ? (lost / total * 100).clamp(0, 100).toDouble() : 0;
  }
  double? concealed;
  final concealedSamples = current.concealedSamples;
  final duration = current.totalSamplesDuration;
  final rate = current.clockRate ?? 48000;
  if (concealedSamples != null && duration != null && duration > 0) {
    concealed = (concealedSamples / (duration * rate) * 100)
        .clamp(0, 100)
        .toDouble();
  }
  return VoiceStreamSummary(
    kbps: kbps,
    lossPercent: loss,
    jitterMs: current.jitterSeconds == null
        ? null
        : current.jitterSeconds! * 1000,
    roundTripMs: current.roundTripSeconds == null
        ? null
        : current.roundTripSeconds! * 1000,
    concealedPercent: concealed,
    codecLabel: codecLabel(
      current.codec,
      channels: current.channels,
      clockRate: current.clockRate,
    ),
  );
}

/// `audio/opus` + 48000 + 2 → `Opus 48 kHz stereo`.
String? codecLabel(String? mimeType, {num? channels, num? clockRate}) {
  if (mimeType == null || mimeType.isEmpty) return null;
  final name = mimeType.split('/').last;
  final pretty = name.isEmpty
      ? name
      : name[0].toUpperCase() + name.substring(1).toLowerCase();
  final parts = [pretty];
  if (clockRate != null && clockRate > 0) {
    parts.add('${(clockRate / 1000).round()} kHz');
  }
  if (channels != null && channels > 0) {
    parts.add(channels >= 2 ? 'stereo' : 'mono');
  }
  return parts.join(' ');
}

/// A coarse verdict for the panel's headline: how the link feels.
enum VoiceLinkGrade { good, fair, poor }

/// Grades a stream from its loss and concealment: under 1 % lost or concealed
/// is good, under 5 % fair, beyond that poor. Unknown counters count as good.
VoiceLinkGrade gradeVoiceStream(VoiceStreamSummary s) {
  final worst = [
    s.lossPercent ?? 0,
    s.concealedPercent ?? 0,
  ].reduce((a, b) => a > b ? a : b);
  if (worst >= 5) return VoiceLinkGrade.poor;
  if (worst >= 1) return VoiceLinkGrade.fair;
  return VoiceLinkGrade.good;
}
