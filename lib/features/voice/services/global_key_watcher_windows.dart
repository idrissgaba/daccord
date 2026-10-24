import 'dart:io' show Platform;

import 'package:flutter/services.dart' show kWindowsToPhysicalKey;
import 'package:win32/win32.dart' show GetAsyncKeyState, MapVirtualKey;

/// Windows reports any key's state to any app, focused or not. Off under
/// `flutter test`, which runs on the host but has no keyboard to watch.
final bool globalKeysSupported =
    Platform.isWindows && !Platform.environment.containsKey('FLUTTER_TEST');

/// Whether the key is held right now.
bool isVirtualKeyDown(int virtualKey) =>
    (GetAsyncKeyState(virtualKey) & 0x8000) != 0;

/// `MAPVK_VSC_TO_VK_EX`: scan code (with its 0xE0 prefix for extended keys)
/// to a virtual key that tells left and right modifiers apart.
const _scanCodeToVirtualKey = 3;

/// The Windows virtual key of the physical key [usbHidUsage], through the scan
/// code Flutter itself maps it from.
int? virtualKeyFor(int usbHidUsage) {
  if (!globalKeysSupported) return null;
  for (final entry in kWindowsToPhysicalKey.entries) {
    if (entry.value.usbHidUsage != usbHidUsage) continue;
    final vk = MapVirtualKey(entry.key, _scanCodeToVirtualKey);
    return vk == 0 ? null : vk;
  }
  return null;
}
