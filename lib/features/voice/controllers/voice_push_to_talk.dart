part of 'voice.dart';

/// Push-to-talk: the app-wide key hook, the system-wide watcher used on
/// Windows, and the release delay. Split from [VoiceController] for size.
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
