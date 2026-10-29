import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Closes the page it wraps when Escape is pressed, as settings pages do in
/// other chat apps. Escape still reaches anything focused inside first (a
/// dropdown or a dialog closes itself before the page does).
class EscapeToClose extends StatelessWidget {
  const EscapeToClose({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
