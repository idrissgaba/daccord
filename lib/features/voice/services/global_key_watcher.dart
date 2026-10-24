import 'dart:async';

import 'package:bonfire/features/voice/services/global_key_watcher_stub.dart'
    if (dart.library.ffi) 'package:bonfire/features/voice/services/global_key_watcher_windows.dart'
    as platform;
import 'package:flutter/foundation.dart';

/// Watches one key system-wide, so push-to-talk keeps working while another
/// app has focus. Only the Windows desktop app can (see [supported]);
/// elsewhere push-to-talk stays focus-only.
class GlobalKeyWatcher {
  GlobalKeyWatcher({
    bool Function(int virtualKey)? isDown,
    int? Function(int usbHidUsage)? virtualKeyFor,
    bool? supported,
    this.interval = const Duration(milliseconds: 15),
  }) : _isDown = isDown ?? platform.isVirtualKeyDown,
       _virtualKeyFor = virtualKeyFor ?? platform.virtualKeyFor,
       supported = supported ?? platform.globalKeysSupported;

  final bool Function(int virtualKey) _isDown;
  final int? Function(int usbHidUsage) _virtualKeyFor;

  /// Whether this platform can watch keys outside the app.
  final bool supported;

  /// How often the key is sampled.
  final Duration interval;

  Timer? _timer;
  int? _watchedUsage;
  bool _down = false;

  /// Whether a key is being watched.
  bool get watching => _timer != null;

  /// Starts reporting the key with USB HID [usbHidUsage] (a
  /// `PhysicalKeyboardKey.usbHidUsage`) to [onChanged] on every press and
  /// release. Returns false when the key can't be watched here.
  bool watch(int usbHidUsage, ValueChanged<bool> onChanged) {
    if (watching && _watchedUsage == usbHidUsage) return true;
    stop();
    if (!supported) return false;
    final vk = _virtualKeyFor(usbHidUsage);
    if (vk == null) return false;
    _watchedUsage = usbHidUsage;
    _timer = Timer.periodic(interval, (_) {
      final down = _isDown(vk);
      if (down == _down) return;
      _down = down;
      onChanged(down);
    });
    return true;
  }

  /// Stops watching. A key still held is not reported released; callers
  /// release push-to-talk themselves.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _watchedUsage = null;
    _down = false;
  }
}
