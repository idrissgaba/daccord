import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/utils/permissions.dart';
import 'package:bonfire/features/spaces/controllers/space_events.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/utils/event_logic.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the signed-in member may plan events in [spaceId].
bool _canManageEvents(WidgetRef ref, String spaceId) {
  final space = ref.watch(
    spacesControllerProvider.select(
      (spaces) => spaces?.firstWhereOrNull((s) => s.id == spaceId),
    ),
  );
  return accordHasPermission(
    ref.watchAccordPermissions(space, spaceId),
    AccordPermission.manageEvents,
  );
}

String _cdn(String? cdnUrl, String path) =>
    path.startsWith('http') ? path : '${cdnUrl ?? ''}$path';

/// The "Events" row at the top of a space's channel list: a red LIVE line
/// while an event is under way, otherwise how many are coming up.
class SpaceEventsEntry extends ConsumerWidget {
  const SpaceEventsEntry({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverKey = ref.watchActiveServerKey() ?? '';
    final events =
        ref.watch(spaceEventsControllerProvider(serverKey, spaceId)) ??
        const <AccordScheduledEvent>[];
    final colors = BonfireThemeExtension.of(context);
    final theme = Theme.of(context);
    final live = events.where((e) => e.isActive).firstOrNull;
    final label = live != null
        ? 'LIVE · ${live.name}'
        : events.isEmpty
        ? 'Events'
        : events.length == 1
        ? '1 Event'
        : '${events.length} Events';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Material(
        color: live != null
            ? colors.red.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: const Key('space-events-entry'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => showSpaceEvents(context, spaceId: spaceId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Icon(
                  live != null ? Icons.podcasts : Icons.event,
                  size: 18,
                  color: live != null ? colors.red : colors.dirtyWhite,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: live != null ? colors.red : colors.dirtyWhite,
                      fontWeight: live != null ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the space's events: what's coming up, who's interested, and (for
/// members who manage events) planning, starting, ending and cancelling.
Future<void> showSpaceEvents(BuildContext context, {required String spaceId}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SpaceEventsDialog(spaceId: spaceId),
  );
}

class SpaceEventsDialog extends ConsumerWidget {
  const SpaceEventsDialog({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final serverKey = ref.watchActiveServerKey() ?? '';
    final events = ref.watch(spaceEventsControllerProvider(serverKey, spaceId));
    final canManage = _canManageEvents(ref, spaceId);
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 560, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.event, size: 18, color: colors.dirtyWhite),
                  const SizedBox(width: 8),
                  Text('Events', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (canManage)
                    FilledButton.icon(
                      key: const Key('event-create'),
                      onPressed: () =>
                          showEventEditor(context, spaceId: spaceId),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Create event'),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: events == null
                    ? const LoadingView()
                    : events.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          canManage
                              ? 'No events yet. Plan one for everyone!'
                              : 'No events coming up.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: events.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) => EventCard(
                          event: events[index],
                          canManage: canManage,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One event: cover, when, name, description, where, how many are
/// interested, and its actions.
class EventCard extends ConsumerStatefulWidget {
  const EventCard({super.key, required this.event, required this.canManage});

  final AccordScheduledEvent event;
  final bool canManage;

  @override
  ConsumerState<EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<EventCard> {
  bool _busy = false;

  AccordScheduledEvent get _event => widget.event;

  String get _serverKey => ref.readActiveServerKey() ?? '';

  /// Runs [action] and applies the event it answers with.
  Future<void> _run(
    Future<RestResult> Function(AccordClient client) action,
    String failure,
  ) async {
    final client = ref.accordClient;
    if (client == null) return;
    setState(() => _busy = true);
    final result = await action(client);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      showInfoSnack(context, result.errorMessageOr(failure));
      return;
    }
    final controller = ref.read(
      spaceEventsControllerProvider(_serverKey, _event.spaceId).notifier,
    );
    final data = result.data;
    if (data is AccordScheduledEvent) {
      if (eventIsOpen(data)) {
        controller.upsert(data);
      } else {
        controller.remove(data.id);
      }
    } else {
      controller.remove(_event.id);
    }
  }

  void _setStatus(String status, String failure) => _run(
    (client) =>
        client.events.update(_event.spaceId, _event.id, {'status': status}),
    failure,
  );

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${_event.name}?',
      message: 'It disappears for everyone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true || !mounted) return;
    await _run(
      (client) => client.events.delete(_event.spaceId, _event.id),
      'Could not delete the event',
    );
  }

  Future<void> _addToCalendar(String where) async {
    final ics = buildIcs(_event, where: where, now: DateTime.now());
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: 'Add to calendar',
        fileName: icsFileName(_event),
        type: FileType.custom,
        allowedExtensions: const ['ics'],
        bytes: Uint8List.fromList(utf8.encode(ics)),
      );
    } catch (_) {
      if (mounted) showInfoSnack(context, 'Could not save the calendar file.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final event = _event;
    final channels =
        ref.watch(
          accordChannelsControllerProvider(_serverKey, event.spaceId),
        ) ??
        const <AccordChannel>[];
    final channel = channels.firstWhereOrNull((c) => c.id == event.channelId);
    final where = event.isVoice
        ? (channel == null ? 'Voice channel' : '🔊 ${channel.name}')
        : (event.location ?? '');
    final cdnUrl = ref.watchCdnUrl();
    final interested = event.interested ?? false;
    final inVoiceHere = ref.watch(
      voiceControllerProvider.select((v) => v.channelId == event.channelId),
    );

    return Container(
      key: ValueKey('event-${event.id}'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.darkGray,
        borderRadius: BorderRadius.circular(8),
        border: event.isActive ? Border.all(color: colors.red) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (event.image != null)
            CachedNetworkImage(
              imageUrl: _cdn(cdnUrl, event.image!),
              height: 120,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => const SizedBox.shrink(),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventWhenLabel(event, DateTime.now()),
                  style: theme.textTheme.labelMedium!.copyWith(
                    color: event.isActive ? colors.red : colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(event.name, style: theme.textTheme.titleMedium),
                if (event.description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    event.description!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      event.isVoice ? Icons.volume_up : Icons.place_outlined,
                      size: 16,
                      color: colors.gray,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        where,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: colors.gray,
                        ),
                      ),
                    ),
                    Icon(Icons.people_outline, size: 16, color: colors.gray),
                    const SizedBox(width: 4),
                    Text(
                      '${event.userCount} interested',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.gray,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (event.isActive &&
                        event.isVoice &&
                        event.channelId != null &&
                        !inVoiceHere)
                      FilledButton.icon(
                        key: ValueKey('event-join-${event.id}'),
                        onPressed: () => ref
                            .read(voiceControllerProvider.notifier)
                            .join(event.channelId!, event.spaceId),
                        icon: const Icon(Icons.call, size: 16),
                        label: const Text('Join'),
                      ),
                    OutlinedButton.icon(
                      key: ValueKey('event-interested-${event.id}'),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              (client) => client.events.setInterested(
                                event.spaceId,
                                event.id,
                                !interested,
                              ),
                              'Could not update your interest',
                            ),
                      icon: Icon(
                        interested ? Icons.check : Icons.notifications_none,
                        size: 16,
                      ),
                      label: Text(interested ? 'Interested' : 'Interested?'),
                    ),
                    IconButton(
                      tooltip: 'Add to calendar',
                      onPressed: () => _addToCalendar(where),
                      icon: const Icon(Icons.event_available, size: 18),
                    ),
                    if (widget.canManage)
                      PopupMenuButton<String>(
                        key: ValueKey('event-menu-${event.id}'),
                        tooltip: 'Manage event',
                        enabled: !_busy,
                        onSelected: (action) {
                          switch (action) {
                            case 'start':
                              _setStatus('active', 'Could not start the event');
                            case 'end':
                              _setStatus(
                                'completed',
                                'Could not end the event',
                              );
                            case 'cancel':
                              _setStatus(
                                'canceled',
                                'Could not cancel the event',
                              );
                            case 'edit':
                              showEventEditor(
                                context,
                                spaceId: event.spaceId,
                                existing: event,
                              );
                            case 'delete':
                              _delete();
                          }
                        },
                        itemBuilder: (_) => [
                          if (!event.isActive)
                            const PopupMenuItem(
                              value: 'start',
                              child: Text('Start now'),
                            ),
                          if (event.isActive)
                            const PopupMenuItem(
                              value: 'end',
                              child: Text('End event'),
                            ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          if (!event.isActive)
                            const PopupMenuItem(
                              value: 'cancel',
                              child: Text('Cancel event'),
                            ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Delete',
                              style: TextStyle(color: colors.red),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Plans a new event in [spaceId], or edits [existing].
Future<void> showEventEditor(
  BuildContext context, {
  required String spaceId,
  AccordScheduledEvent? existing,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => EventEditorDialog(spaceId: spaceId, existing: existing),
  );
}

class EventEditorDialog extends ConsumerStatefulWidget {
  const EventEditorDialog({super.key, required this.spaceId, this.existing});

  final String spaceId;
  final AccordScheduledEvent? existing;

  @override
  ConsumerState<EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends ConsumerState<EventEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _location;
  late bool _voice;
  String? _channelId;
  late DateTime _start;
  DateTime? _end;
  String? _image;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _voice = e?.isVoice ?? true;
    _channelId = e?.channelId;
    final now = DateTime.now();
    _start =
        e?.start?.toLocal() ??
        DateTime(now.year, now.month, now.day, now.hour + 1);
    _end = e?.end?.toLocal();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null) return;
    setState(() => _image = AccordCDN.buildDataUri(file!.bytes!, file.name));
  }

  Future<void> _save() async {
    final error = eventFormError(
      name: _name.text,
      voice: _voice,
      channelId: _channelId,
      location: _location.text,
      start: _start,
      end: _end,
      now: widget.existing == null ? DateTime.now() : DateTime(2000),
    );
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final client = ref.accordClient;
    if (client == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = eventPayload(
      name: _name.text,
      description: _description.text,
      voice: _voice,
      channelId: _channelId,
      location: _location.text,
      start: _start,
      end: _end,
    );
    if (_image != null) body['image'] = _image;
    final existing = widget.existing;
    final result = existing == null
        ? await client.events.create(widget.spaceId, body)
        : await client.events.update(widget.spaceId, existing.id, body);
    if (!mounted) return;
    if (!result.ok || result.data is! AccordScheduledEvent) {
      setState(() {
        _saving = false;
        _error = result.errorMessageOr('Could not save the event');
      });
      return;
    }
    ref
        .read(
          spaceEventsControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.spaceId,
          ).notifier,
        )
        .upsert(result.data as AccordScheduledEvent);
    Navigator.of(context).pop();
  }

  String _when(DateTime? time) => time == null
      ? 'None'
      : '${time.day}/${time.month}/${time.year} ${eventClock(time)}';

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final voiceChannels =
        (ref.watch(
                  accordChannelsControllerProvider(
                    ref.watchActiveServerKey() ?? '',
                    widget.spaceId,
                  ),
                ) ??
                const <AccordChannel>[])
            .where((c) => c.type == 'voice')
            .toList();
    return AlertDialog(
      title: Text(widget.existing == null ? 'Create event' : 'Edit event'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                key: const Key('event-kind'),
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.volume_up),
                    label: Text('Voice channel'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.place_outlined),
                    label: Text('Somewhere else'),
                  ),
                ],
                selected: {_voice},
                onSelectionChanged: (value) =>
                    setState(() => _voice = value.first),
              ),
              const SizedBox(height: 8),
              if (_voice)
                DropdownButtonFormField<String>(
                  key: const Key('event-channel'),
                  initialValue: voiceChannels.any((c) => c.id == _channelId)
                      ? _channelId
                      : null,
                  decoration: const InputDecoration(labelText: 'Voice channel'),
                  items: [
                    for (final channel in voiceChannels)
                      DropdownMenuItem(
                        value: channel.id,
                        child: Text(channel.name ?? channel.id),
                      ),
                  ],
                  onChanged: (value) => setState(() => _channelId = value),
                )
              else
                TextField(
                  key: const Key('event-location'),
                  controller: _location,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              TextField(
                key: const Key('event-name'),
                controller: _name,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                key: const Key('event-description'),
                controller: _description,
                maxLength: 1000,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              ListTile(
                key: const Key('event-start'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: const Text('Starts'),
                subtitle: Text(_when(_start)),
                onTap: () async {
                  final picked = await _pickDateTime(_start);
                  if (picked != null) setState(() => _start = picked);
                },
              ),
              ListTile(
                key: const Key('event-end'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule_outlined),
                title: Text(_voice ? 'Ends (optional)' : 'Ends'),
                subtitle: Text(_when(_end)),
                trailing: _end == null
                    ? null
                    : IconButton(
                        tooltip: 'No end time',
                        onPressed: () => setState(() => _end = null),
                        icon: const Icon(Icons.clear, size: 18),
                      ),
                onTap: () async {
                  final picked = await _pickDateTime(
                    _end ?? _start.add(const Duration(hours: 2)),
                  );
                  if (picked != null) setState(() => _end = picked);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image_outlined),
                title: Text(
                  _image == null ? 'Add a cover image' : 'Cover image chosen',
                ),
                onTap: _pickImage,
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
          key: const Key('event-save'),
          onPressed: _saving ? null : _save,
          child: Text(widget.existing == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}
