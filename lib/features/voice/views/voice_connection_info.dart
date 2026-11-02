import 'dart:async';

import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/utils/voice_stats.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the voice link's connection details — codec, bitrate, loss, jitter,
/// round-trip time and audio concealment, for us and for each participant —
/// refreshed every two seconds while open. The counterpart of other chat
/// apps' "voice connected" debug popover: it tells a bad network apart from a
/// bad microphone.
Future<void> showVoiceConnectionInfo(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _VoiceConnectionInfoDialog(),
  );
}

class _VoiceConnectionInfoDialog extends ConsumerStatefulWidget {
  const _VoiceConnectionInfoDialog();

  @override
  ConsumerState<_VoiceConnectionInfoDialog> createState() =>
      _VoiceConnectionInfoDialogState();
}

class _VoiceConnectionInfoDialogState
    extends ConsumerState<_VoiceConnectionInfoDialog> {
  static const _interval = Duration(seconds: 2);

  Timer? _timer;
  VoiceLinkSnapshot? _previous;
  VoiceLinkSnapshot? _current;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(_interval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling) return;
    final session = ref.read(voiceControllerProvider.notifier).session;
    if (session == null) return;
    _polling = true;
    try {
      final next = await session.collectStats();
      if (!mounted) return;
      setState(() {
        _previous = _current;
        _current = next;
      });
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final voice = ref.watch(voiceControllerProvider);
    final snapshot = _current;
    final serverKey = ref.readActiveServerKey() ?? '';
    final spaceId = voice.spaceId;
    final members = spaceId == null
        ? null
        : ref.watch(accordMembersControllerProvider(serverKey, spaceId));
    final users = ref.watch(accordUsersControllerProvider(serverKey));
    final ensure = ref
        .read(accordUsersControllerProvider(serverKey).notifier)
        .ensure;

    final rows = <Widget>[];
    if (snapshot == null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Measuring…',
            style: theme.textTheme.bodyMedium!.copyWith(color: colors.gray),
          ),
        ),
      );
    } else {
      final out = snapshot.outgoing;
      if (out != null) {
        rows.add(
          _StreamCard(
            title: 'Your microphone',
            subtitle: 'Sending to the server',
            summary: summarizeVoiceStream(out, previous: _previous?.outgoing),
            outgoing: true,
          ),
        );
      } else {
        rows.add(
          ListTile(
            leading: Icon(Icons.mic_off, color: colors.gray),
            title: const Text('Your microphone'),
            subtitle: const Text('Muted or not published'),
          ),
        );
      }
      if (snapshot.incoming.isEmpty) {
        rows.add(
          ListTile(
            leading: Icon(Icons.hearing_disabled, color: colors.gray),
            title: const Text('Nobody else is sending audio'),
          ),
        );
      }
      for (final entry in snapshot.incoming.entries) {
        final name = accordAuthorName(
          entry.key,
          members: members,
          users: users,
          ensure: ensure,
        );
        rows.add(
          _StreamCard(
            title: name,
            subtitle: 'Receiving',
            summary: summarizeVoiceStream(
              entry.value,
              previous: _previous?.incoming[entry.key],
            ),
            outgoing: false,
          ),
        );
      }
    }

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Voice connection')),
          _QualityChip(quality: snapshot?.quality ?? 'unknown'),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...rows,
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'Loss and concealment above 1 % start to be audible; above '
                  '5 % words drop. High jitter or round-trip time points at '
                  'the network, not the microphone.',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.gray,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// One stream's numbers: bitrate, loss, jitter, and RTT (outgoing) or
/// concealment (incoming), with a coloured grade dot.
class _StreamCard extends StatelessWidget {
  const _StreamCard({
    required this.title,
    required this.subtitle,
    required this.summary,
    required this.outgoing,
  });

  final String title;
  final String subtitle;
  final VoiceStreamSummary summary;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final grade = gradeVoiceStream(summary);
    final gradeColor = switch (grade) {
      VoiceLinkGrade.good => colors.green,
      VoiceLinkGrade.fair => colors.yellow,
      VoiceLinkGrade.poor => colors.red,
    };
    String pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)} %';
    String ms(double? v) => v == null ? '—' : '${v.round()} ms';
    final cells = <(String, String)>[
      ('Bitrate', '${summary.kbps.round()} kbps'),
      ('Loss', pct(summary.lossPercent)),
      ('Jitter', ms(summary.jitterMs)),
      if (outgoing)
        ('Round trip', ms(summary.roundTripMs))
      else
        ('Concealed', pct(summary.concealedPercent)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.darkGray,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: gradeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  summary.codecLabel ?? subtitle,
                  style: theme.textTheme.labelSmall!.copyWith(
                    color: colors.gray,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (label, value) in cells)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: theme.textTheme.labelSmall!.copyWith(
                            color: colors.gray,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                        Text(value, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The server's connection-quality verdict for our link.
class _QualityChip extends StatelessWidget {
  const _QualityChip({required this.quality});

  final String quality;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final (label, color) = switch (quality) {
      'excellent' => ('Excellent', colors.green),
      'good' => ('Good', colors.green),
      'poor' => ('Poor', colors.yellow),
      'lost' => ('Lost', colors.red),
      _ => ('Measuring', colors.gray),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.network_check, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
