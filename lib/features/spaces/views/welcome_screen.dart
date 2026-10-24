import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows [spaceId]'s welcome screen once, the first time the space is opened
/// with one enabled. Renders nothing itself.
class WelcomeScreenGate extends ConsumerStatefulWidget {
  const WelcomeScreenGate({
    super.key,
    required this.spaceId,
    required this.onOpenChannel,
  });

  final String spaceId;
  final ValueChanged<String> onOpenChannel;

  @override
  ConsumerState<WelcomeScreenGate> createState() => _WelcomeScreenGateState();
}

class _WelcomeScreenGateState extends ConsumerState<WelcomeScreenGate> {
  String? _checked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void didUpdateWidget(WelcomeScreenGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spaceId != widget.spaceId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final spaceId = widget.spaceId;
    if (!mounted || _checked == spaceId) return;
    _checked = spaceId;
    final serverKey = ref.readActiveServerKey() ?? '';
    final settings = ref.read(settingsControllerProvider);
    if (settings.isWelcomeSeen(serverKey, spaceId)) return;
    final client = ref.accordClient;
    if (client == null) return;
    final result = await client.welcomeScreen.get(spaceId);
    final screen = result.data;
    if (!mounted || widget.spaceId != spaceId) return;
    if (!result.ok || screen is! AccordWelcomeScreen || !screen.enabled) return;
    ref
        .read(settingsControllerProvider.notifier)
        .markWelcomeSeen(serverKey, spaceId);
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => WelcomeScreenDialog(spaceId: spaceId, screen: screen),
    );
    if (picked != null && mounted) widget.onOpenChannel(picked);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// "Welcome to `space`!" with the description and the recommended channels;
/// tapping one closes the dialog with its id.
class WelcomeScreenDialog extends ConsumerWidget {
  const WelcomeScreenDialog({
    super.key,
    required this.spaceId,
    required this.screen,
  });

  final String spaceId;
  final AccordWelcomeScreen screen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final space = ref.watch(
      spacesControllerProvider.select(
        (spaces) => spaces?.firstWhereOrNull((s) => s.id == spaceId),
      ),
    );
    final channels =
        ref.watch(
          accordChannelsControllerProvider(
            ref.watchActiveServerKey() ?? '',
            spaceId,
          ),
        ) ??
        const <AccordChannel>[];
    return AlertDialog(
      key: const Key('welcome-screen'),
      title: Text('Welcome to ${space?.name ?? 'the space'}!'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (screen.description != null)
              Text(screen.description!, style: theme.textTheme.bodyMedium),
            if (screen.channels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'WHERE TO START',
                style: theme.textTheme.labelSmall!.copyWith(
                  color: colors.gray,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              for (final item in screen.channels)
                ListTile(
                  key: ValueKey('welcome-channel-${item.channelId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    item.emoji ?? '#',
                    style: const TextStyle(fontSize: 20),
                  ),
                  title: Text(
                    item.description,
                    style: theme.textTheme.bodyMedium,
                  ),
                  subtitle: Text(
                    '#${channels.firstWhereOrNull((c) => c.id == item.channelId)?.name ?? ''}',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.gray,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(item.channelId),
                ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

/// Edits [spaceId]'s welcome screen (needs `manage_space`).
Future<void> showWelcomeScreenEditor(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => WelcomeScreenEditor(spaceId: spaceId),
  );
}

class WelcomeScreenEditor extends ConsumerStatefulWidget {
  const WelcomeScreenEditor({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<WelcomeScreenEditor> createState() =>
      _WelcomeScreenEditorState();
}

class _Row {
  _Row({this.channelId, String description = '', String emoji = ''})
    : description = TextEditingController(text: description),
      emoji = TextEditingController(text: emoji);

  String? channelId;
  final TextEditingController description;
  final TextEditingController emoji;
}

class _WelcomeScreenEditorState extends ConsumerState<WelcomeScreenEditor> {
  final _description = TextEditingController();
  final _rows = <_Row>[];
  bool _enabled = false;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    for (final row in _rows) {
      row.description.dispose();
      row.emoji.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final client = ref.accordClient;
    if (client == null) return;
    final result = await client.welcomeScreen.get(widget.spaceId);
    if (!mounted) return;
    final screen = result.data;
    setState(() {
      _loaded = true;
      if (screen is AccordWelcomeScreen) {
        _enabled = screen.enabled;
        _description.text = screen.description ?? '';
        _rows.addAll([
          for (final c in screen.channels)
            _Row(
              channelId: c.channelId,
              description: c.description,
              emoji: c.emoji ?? '',
            ),
        ]);
      } else {
        _error = result.errorMessageOr('Could not load the welcome screen');
      }
    });
  }

  Future<void> _save() async {
    final client = ref.accordClient;
    if (client == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final screen = AccordWelcomeScreen(
      enabled: _enabled,
      description: _description.text.trim(),
      channels: [
        for (final row in _rows)
          if (row.channelId != null)
            AccordWelcomeChannel(
              channelId: row.channelId!,
              description: row.description.text.trim(),
              emoji: row.emoji.text.trim().isEmpty
                  ? null
                  : row.emoji.text.trim(),
            ),
      ],
    );
    final result = await client.welcomeScreen.update(widget.spaceId, screen);
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _saving = false;
        _error = result.errorMessageOr('Could not save the welcome screen');
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final channels =
        (ref.watch(
                  accordChannelsControllerProvider(
                    ref.watchActiveServerKey() ?? '',
                    widget.spaceId,
                  ),
                ) ??
                const <AccordChannel>[])
            .where((c) => c.type != 'category')
            .toList();
    return AlertDialog(
      title: const Text('Welcome screen'),
      content: SizedBox(
        width: 480,
        child: !_loaded
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      key: const Key('welcome-enabled'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show to new members'),
                      value: _enabled,
                      onChanged: (v) => setState(() => _enabled = v),
                    ),
                    TextField(
                      key: const Key('welcome-description'),
                      controller: _description,
                      maxLength: 140,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'What is this space about?',
                      ),
                    ),
                    for (final row in _rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 54,
                              child: TextField(
                                controller: row.emoji,
                                maxLength: 4,
                                decoration: const InputDecoration(
                                  labelText: 'Emoji',
                                  counterText: '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: DropdownButtonFormField<String>(
                                initialValue:
                                    channels.any((c) => c.id == row.channelId)
                                    ? row.channelId
                                    : null,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Channel',
                                ),
                                items: [
                                  for (final c in channels)
                                    DropdownMenuItem(
                                      value: c.id,
                                      child: Text(
                                        '#${c.name ?? c.id}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) =>
                                    setState(() => row.channelId = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: row.description,
                                maxLength: 50,
                                decoration: const InputDecoration(
                                  labelText: 'Why go there',
                                  counterText: '',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () =>
                                  setState(() => _rows.remove(row)),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                    if (_rows.length < 5)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('welcome-add-channel'),
                          onPressed: () => setState(() => _rows.add(_Row())),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Recommend a channel'),
                        ),
                      ),
                    if (_error != null)
                      Text(_error!, style: TextStyle(color: colors.red)),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('welcome-save'),
          onPressed: _saving || !_loaded ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
