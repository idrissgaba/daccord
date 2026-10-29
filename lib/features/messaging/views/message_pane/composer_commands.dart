part of 'message_pane.dart';

/// Slash commands: the /name popup, the picked command's option form, and running it. Split from [_ComposerState] for size.
mixin _ComposerCommands
    on ConsumerState<_Composer>, _ComposerAttachments, _ComposerMentions {
  void _saveDraft(String channelId, String text);

  /// The `/name` being typed, or null when the command popup is hidden.
  String? _slashQuery;

  /// The slash command picked from the popup, whose options are being filled
  /// in; null in plain message mode.
  AccordCommand? _command;

  /// Shows, updates or hides the slash command popup.
  void _updateSlashState(String text) {
    final query = widget.spaceId == null ? null : slashQuery(text);
    if (query == _slashQuery) return;
    setState(() => _slashQuery = query);
  }

  /// Switches the box to filling in [command]'s options.
  void _pickCommand(AccordCommand command) {
    _controller.clear();
    _saveDraft(widget.channelId, '');
    setState(() {
      _slashQuery = null;
      _mention = null;
      _command = command;
    });
  }

  void _cancelCommand() {
    setState(() => _command = null);
    _focusNode.requestFocus();
  }

  /// Runs [command] with [options]; resolves to the reason it failed, or
  /// null. The bot's answer arrives as a message; until it does, the box says
  /// the command is on its way.
  Future<String?> _runCommand(
    AccordCommand command,
    List<Map<String, dynamic>> options,
  ) async {
    final client = ref.accordClient;
    if (client == null) return 'Not connected.';
    final result = await client.interactions.runCommand(
      channelId: widget.channelId,
      commandId: command.id,
      options: options,
    );
    final data = result.data;
    final id = result.ok && data is Map ? data['id'] as String? : null;
    if (id == null) {
      return result.errorMessageOr('Could not run /${command.name}');
    }
    ref
        .read(interactionTrackerProvider.notifier)
        .started(
          PendingInteraction(
            id: id,
            channelId: widget.channelId,
            commandName: command.name,
          ),
        );
    if (mounted && identical(_command, command)) {
      setState(() => _command = null);
      _focusNode.requestFocus();
    }
    return null;
  }

  /// `/name text` typed in full: runs the command when the text fills it,
  /// opens its form when it needs more, or picks the top match of a partial
  /// `/na`. Returns whether [text] was handled as a command. Decides
  /// synchronously, so the box is cleared in the same turn as a plain send
  /// (the Linux send barrier relies on it).
  bool _sendAsCommand(String text) {
    final spaceId = widget.spaceId;
    if (spaceId == null || !text.startsWith('/') || _attachments.isNotEmpty) {
      return false;
    }
    final commands =
        ref.read(spaceCommandsControllerProvider(_serverKey, spaceId)) ??
        const <AccordCommand>[];
    if (commands.isEmpty) return false;
    final quick = parseQuickCommand(text, commands);
    if (quick != null) {
      _controller.clear();
      _saveDraft(widget.channelId, '');
      setState(() => _slashQuery = null);
      unawaited(
        _runCommand(quick.command, quick.options).then((error) {
          if (error == null || !mounted) return;
          if (_controller.text.isEmpty) _controller.text = text;
          setState(() => _error = error);
        }),
      );
      return true;
    }
    final typedName = RegExp(r'^/(\S+)').firstMatch(text)?.group(1);
    final exact = commands.where((c) => c.name == typedName).firstOrNull;
    final pick =
        exact ??
        (slashQuery(text) == null
            ? null
            : matchCommands(commands, slashQuery(text)!).firstOrNull);
    if (pick == null) return false;
    _pickCommand(pick);
    return true;
  }
}
