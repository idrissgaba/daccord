part of 'voice.dart';

/// Push-to-talk: the app-wide key hook, the system-wide watchers used on
/// Windows (push-to-talk, and the mute/deafen keybinds), and the release
/// delay. Split from [VoiceController] for size.
mixin _PushToTalk on _$VoiceController {
  VoiceSession? get _session;
  AfkMonitor? get _afkMonitor;

  /// Hooks [_onKeyEvent] into the app-wide keyboard. Returns false where no
  /// services binding exists (pure-Dart tests), which have no keyboard anyway.
  bool _attachKeyHook() {
    try {
      HardwareKeyboard.instance.addHandler(_onKeyEvent);
      return true;
    } on FlutterError {
      return false;
    }
  }

  /// Pending close of the push-to-talk mic after the key was released.
  Timer? _releasePushToTalk;

  /// Watches the push-to-talk key outside the app too (Windows desktop), so it
  /// works while a game or another app has focus.
  final _globalKeys = GlobalKeyWatcher();

  /// Watches the push-to-talk key system-wide while in a call with
  /// push-to-talk on.
  void _syncGlobalPushToTalk() {
    final settings = ref.read(settingsControllerProvider);
    if (settings.pushToTalk && state.isConnected) {
      _globalKeys.watch(settings.pushToTalkKey, setPushToTalkPressed);
    } else if (_globalKeys.watching) {
      _globalKeys.stop();
      setPushToTalkPressed(false);
    }
  }

  /// Watches the mute and deafen keybinds outside the app too (Windows
  /// desktop), so they work while a game or another app has focus.
  final _globalShortcuts = GlobalChordWatcher<(HomeShortcut, int)>();

  /// Whether the mute/deafen keybinds are being watched system-wide; the
  /// home screen's own key handler then leaves them alone, which would
  /// otherwise toggle twice while the app has focus.
  bool get watchesVoiceShortcutsGlobally => _globalShortcuts.watching;

  /// Watches the mute and deafen keybinds system-wide while in a call.
  void _syncGlobalVoiceShortcuts() {
    if (!state.isConnected) {
      _globalShortcuts.stop();
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    final bindings = effectiveBindings(
      settings.keybinds,
      disabledDefaults: settings.disabledDefaultKeybinds,
    );
    // Keyed by position too: a recorded chord and a built-in one may both
    // be in force for the same action, as they are in the app.
    final chords = <(HomeShortcut, int), GlobalChord>{};
    for (final (i, binding) in bindings.indexed) {
      if (binding.shortcut != HomeShortcut.toggleMute &&
          binding.shortcut != HomeShortcut.toggleDeafen) {
        continue;
      }
      final usage = binding.physicalUsage;
      if (usage == null) continue;
      chords[(binding.shortcut, i)] = GlobalChord(
        usage,
        control: binding.control,
        shift: binding.shift,
        alt: binding.alt,
      );
    }
    if (chords.isEmpty) {
      _globalShortcuts.stop();
      return;
    }
    _globalShortcuts.watch(chords, (pressed) {
      if (pressed.$1 == HomeShortcut.toggleMute) {
        toggleMute();
      } else {
        toggleDeafen();
      }
    });
  }

  void toggleMute();
  void toggleDeafen();

  /// App-wide key hook for push-to-talk. Never consumes the event, so the key
  /// still types normally in text fields. Stands down while the key is watched
  /// system-wide, which sees the same presses.
  bool _onKeyEvent(KeyEvent event) {
    if (event is KeyRepeatEvent || !state.isConnected) return false;
    if (_globalKeys.watching) return false;
    final settings = ref.read(settingsControllerProvider);
    if (!settings.pushToTalk ||
        event.physicalKey.usbHidUsage != settings.pushToTalkKey) {
      return false;
    }
    setPushToTalkPressed(event is KeyDownEvent);
    return false;
  }

  /// Push-to-talk key or voice-bar button pressed / released. Releasing keeps
  /// the mic open for [pushToTalkReleaseDelay] so the last word isn't cut.
  void setPushToTalkPressed(bool pressed) {
    final session = _session;
    if (session == null || !state.isConnected) return;
    _releasePushToTalk?.cancel();
    if (pressed) {
      _afkMonitor?.markActivity();
      unawaited(session.setPushToTalkPressed(true));
    } else {
      _releasePushToTalk = Timer(
        pushToTalkReleaseDelay,
        () => session.setPushToTalkPressed(false),
      );
    }
  }
}
