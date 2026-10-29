import 'package:flutter/gestures.dart';

/// Where the pointer last went down, so a popover (profile card, emoji
/// picker, …) can open beside what was clicked, as in other chat apps.
Offset? _lastPointerDown;
DateTime? _lastPointerDownAt;
bool _tracking = false;

/// Starts recording pointer-down positions for [recentPointerAnchor].
/// Idempotent; the home screen calls it on mount.
void trackPointerAnchor() {
  if (_tracking) return;
  _tracking = true;
  GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
    if (event is PointerDownEvent) {
      _lastPointerDown = event.position;
      _lastPointerDownAt = DateTime.now();
    }
  });
}

/// The position of the last pointer-down, if it happened within [within];
/// null otherwise (a keyboard-driven open, or nothing tracked yet).
Offset? recentPointerAnchor({Duration within = const Duration(seconds: 2)}) {
  final at = _lastPointerDownAt;
  if (at == null || DateTime.now().difference(at) > within) return null;
  return _lastPointerDown;
}
