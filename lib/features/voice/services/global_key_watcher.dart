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

/// One key combination for [GlobalChordWatcher]: a main key (its USB HID
/// usage) and the modifiers that must be held with it, no more, no fewer.
class GlobalChord {
  const GlobalChord(
    this.usbHidUsage, {
    this.control = false,
    this.shift = false,
    this.alt = false,
  });

  final int usbHidUsage;
  final bool control;
  final bool shift;
  final bool alt;

  @override
  bool operator ==(Object other) =>
      other is GlobalChord &&
      other.usbHidUsage == usbHidUsage &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(usbHidUsage, control, shift, alt);
}

/// Watches key combinations system-wide, so the mute and deafen keybinds keep
/// working while another app has focus. Windows desktop only, like
/// [GlobalKeyWatcher]; elsewhere keybinds stay focus-only.
class GlobalChordWatcher<T> {
  GlobalChordWatcher({
    bool Function(int virtualKey)? isDown,
    int? Function(int usbHidUsage)? virtualKeyFor,
    bool? supported,
    this.interval = const Duration(milliseconds: 15),
  }) : _isDown = isDown ?? platform.isVirtualKeyDown,
       _virtualKeyFor = virtualKeyFor ?? platform.virtualKeyFor,
       supported = supported ?? platform.globalKeysSupported;

  /// Windows `VK_CONTROL`, `VK_SHIFT` and `VK_MENU`: either side of each.
  static const _control = 0x11;
  static const _shift = 0x10;
  static const _alt = 0x12;

  final bool Function(int virtualKey) _isDown;
  final int? Function(int usbHidUsage) _virtualKeyFor;

  /// Whether this platform can watch keys outside the app.
  final bool supported;

  /// How often the keys are sampled.
  final Duration interval;

  Timer? _timer;
  Map<T, GlobalChord> _watched = const {};

  /// Chords held at the last sample, so a held chord fires once.
  final Set<T> _held = {};

  /// Whether any chord is being watched.
  bool get watching => _timer != null;

  /// Reports each press of a chord in [chords] to [onPressed] with its key.
  /// Chords whose key can't be watched here are left out; returns whether any
  /// is watched.
  bool watch(Map<T, GlobalChord> chords, ValueChanged<T> onPressed) {
    if (watching && mapEquals(chords, _watched)) return true;
    stop();
    if (!supported) return false;
    final keys = <T, int>{
      for (final entry in chords.entries)
        if (_virtualKeyFor(entry.value.usbHidUsage) case final vk?)
          entry.key: vk,
    };
    if (keys.isEmpty) return false;
    _watched = Map.of(chords);
    _timer = Timer.periodic(interval, (_) {
      final control = _isDown(_control);
      final shift = _isDown(_shift);
      final alt = _isDown(_alt);
      for (final MapEntry(key: id, value: vk) in keys.entries) {
        final chord = _watched[id]!;
        final down =
            _isDown(vk) &&
            chord.control == control &&
            chord.shift == shift &&
            chord.alt == alt;
        if (!down) {
          _held.remove(id);
        } else if (_held.add(id)) {
          onPressed(id);
        }
      }
    });
    return true;
  }

  /// Stops watching.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _watched = const {};
    _held.clear();
  }
}
