import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortcut guide documents the edit keys the editor implements', () {
    final guide = File(
      'docs/troubleshooting/keyboard-shortcuts.md',
    ).readAsStringSync();
    // The inline editor's keys and the ↑ edit request live in the row's
    // editing mixin (message_row_editing.dart).
    final editor = File(
      'lib/features/messaging/views/message_pane/message_row_editing.dart',
    ).readAsStringSync();

    // Escape cancels and ↑ edits: documented, and backed by the editor's
    // key handler and the composer's edit-last-message hook.
    expect(guide, contains('| Escape | Cancel the edit |'));
    expect(guide, contains('| ↑ (empty composer) |'));
    expect(editor, contains('LogicalKeyboardKey.escape'));
    expect(editor, contains('editRequest'));
    expect(guide, contains('choose **Edit**'));
  });
}
