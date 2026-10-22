import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/poll_display.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';

/// A poll inside a message: the question, one row per answer and the vote
/// count. Tapping an answer votes for it (or withdraws the vote); results
/// show once the user has voted or the poll has closed.
class PollView extends StatefulWidget {
  const PollView({super.key, required this.poll, required this.onVote});

  final AccordPoll poll;

  /// Votes for [answerId] (or withdraws the vote, with [remove]); returns the
  /// reason it failed, or null.
  final Future<String?> Function(int answerId, {required bool remove}) onVote;

  @override
  State<PollView> createState() => _PollViewState();
}

class _PollViewState extends State<PollView> {
  int? _busyAnswer;
  String? _error;

  Future<void> _tap(AccordPollAnswer answer) async {
    if (_busyAnswer != null) return;
    setState(() {
      _busyAnswer = answer.answerId;
      _error = null;
    });
    final error = await widget.onVote(
      answer.answerId,
      remove: answer.me == true,
    );
    if (!mounted) return;
    setState(() {
      _busyAnswer = null;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final poll = widget.poll;
    final now = DateTime.now();
    final expires = DateTime.tryParse(poll.expiresAt ?? '');
    final closed = poll.closed || (expires != null && !expires.isAfter(now));
    final showResults = closed || poll.hasMyVote;

    return Container(
      key: const Key('poll-view'),
      constraints: const BoxConstraints(maxWidth: 440),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.darkGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.poll_outlined, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(poll.question, style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          if (!closed)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 24),
              child: Text(
                poll.allowMultiselect
                    ? 'Select one or more answers'
                    : 'Select one answer',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
            ),
          const SizedBox(height: 8),
          for (final answer in poll.answers)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _AnswerRow(
                answer: answer,
                multiselect: poll.allowMultiselect,
                showResults: showResults,
                percent: pollPercent(answer.votes, poll.totalVotes),
                busy: _busyAnswer == answer.answerId,
                onTap: closed ? null : () => _tap(answer),
              ),
            ),
          Text(
            pollFooter(
              totalVotes: poll.totalVotes,
              closed: closed,
              expiresAt: expires,
              now: now,
            ),
            style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall!.copyWith(color: colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnswerRow extends StatelessWidget {
  const _AnswerRow({
    required this.answer,
    required this.multiselect,
    required this.showResults,
    required this.percent,
    required this.busy,
    required this.onTap,
  });

  final AccordPollAnswer answer;
  final bool multiselect;
  final bool showResults;
  final int percent;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final picked = answer.me == true;
    final IconData icon = multiselect
        ? (picked ? Icons.check_box : Icons.check_box_outline_blank)
        : (picked ? Icons.radio_button_checked : Icons.radio_button_unchecked);
    return Material(
      color: colors.foreground,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('poll-answer-${answer.answerId}'),
        onTap: onTap,
        child: Stack(
          children: [
            if (showResults)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: percent / 100,
                  child: ColoredBox(
                    color: (picked ? colors.primary : colors.gray).withValues(
                      alpha: 0.25,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      icon,
                      size: 18,
                      color: picked ? colors.primary : colors.gray,
                    ),
                  const SizedBox(width: 8),
                  if (answer.emoji != null && answer.emoji!.isNotEmpty) ...[
                    Text(answer.emoji!),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(answer.text, style: theme.textTheme.bodyMedium),
                  ),
                  if (showResults)
                    Text(
                      '$percent% (${answer.votes})',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.dirtyWhite,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The answers the user filled in, trimmed, dropping blank ones.
List<String> filledPollAnswers(Iterable<String> answers) => [
  for (final answer in answers)
    if (answer.trim().isNotEmpty) answer.trim(),
];

/// Asks for a poll (question, answers, duration, multiple choice) and creates
/// it through [create], which returns the reason it failed, or null.
Future<void> showCreatePollDialog(
  BuildContext context, {
  required Future<String?> Function({
    required String question,
    required List<String> answers,
    required bool allowMultiselect,
    required int durationHours,
  })
  create,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CreatePollDialog(create: create),
  );
}

class _CreatePollDialog extends StatefulWidget {
  const _CreatePollDialog({required this.create});

  final Future<String?> Function({
    required String question,
    required List<String> answers,
    required bool allowMultiselect,
    required int durationHours,
  })
  create;

  @override
  State<_CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<_CreatePollDialog> {
  final _question = TextEditingController();
  final List<TextEditingController> _answers = [
    TextEditingController(),
    TextEditingController(),
  ];
  int _hours = 24;
  bool _multiselect = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    for (final answer in _answers) {
      answer.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      _question.text.trim().isNotEmpty &&
      filledPollAnswers(_answers.map((c) => c.text)).isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await widget.create(
      question: _question.text.trim(),
      answers: filledPollAnswers(_answers.map((c) => c.text)),
      allowMultiselect: _multiselect,
      durationHours: _hours,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _sending = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return AlertDialog(
      title: const Text('Create a poll'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('poll-question'),
                controller: _question,
                autofocus: true,
                maxLength: maxPollQuestionLength,
                decoration: const InputDecoration(labelText: 'Question'),
                onChanged: (_) => setState(() {}),
              ),
              for (var i = 0; i < _answers.length; i++)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('poll-answer-field-$i'),
                        controller: _answers[i],
                        maxLength: maxPollAnswerLength,
                        decoration: InputDecoration(
                          labelText: 'Answer ${i + 1}',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_answers.length > 1)
                      IconButton(
                        tooltip: 'Remove answer',
                        onPressed: () => setState(() {
                          _answers.removeAt(i).dispose();
                        }),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
              if (_answers.length < maxPollAnswers)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('poll-add-answer'),
                    onPressed: () =>
                        setState(() => _answers.add(TextEditingController())),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add answer'),
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Duration'),
                trailing: DropdownButton<int>(
                  key: const Key('poll-duration'),
                  value: _hours,
                  underline: const SizedBox.shrink(),
                  onChanged: (value) {
                    if (value != null) setState(() => _hours = value);
                  },
                  items: [
                    for (final hours in pollDurationOptions)
                      DropdownMenuItem(
                        value: hours,
                        child: Text(pollDurationLabel(hours)),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                key: const Key('poll-multiselect'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow multiple answers'),
                value: _multiselect,
                onChanged: (value) => setState(() => _multiselect = value),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: colors.red)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('poll-post'),
          onPressed: _sending || !_valid ? null : _submit,
          child: const Text('Post'),
        ),
      ],
    );
  }
}
