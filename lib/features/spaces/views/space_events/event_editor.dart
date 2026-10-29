part of '../space_events.dart';

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
            .where((c) => isVoiceChannelType(c.type))
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
