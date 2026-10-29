import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:bonfire/features/messaging/controllers/accord_emojis.dart';
import 'package:bonfire/features/messaging/utils/emoji_catalog.dart';
import 'package:bonfire/features/messaging/views/message_media_gate.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/shared/components/horizontal_wheel_scroll.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/platform.dart';
import 'package:bonfire/shared/utils/pointer_anchor.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'emoji_picker/panel.dart';

/// The user's selection from the emoji picker. [id] is null for built-in
/// unicode emoji (where [char] is the character to insert/react with — with
/// the chosen skin tone applied); for a custom space emoji [id] is set,
/// [char] is empty, and [imageUrl] points at the rendered glyph.
class EmojiPick {
  const EmojiPick({required this.name, this.char = '', this.id, this.imageUrl});

  final String name;
  final String char;
  final String? id;
  final String? imageUrl;

  bool get isCustom => id != null;

  /// The text inserted into the composer: the char for built-ins, or a
  /// `:name:` shortcode for custom emoji.
  String get composerText => isCustom ? ':$name:' : char;

  /// What a reaction toggle is given: the glyph itself for built-ins (so a
  /// skin tone survives), the name for custom emoji (paired with [id]).
  String get reactionName => isCustom ? name : char;

  /// The token stored in the recents list, from which [_pickFromRecent] can
  /// reconstruct this pick.
  String get recentToken => isCustom ? '$name:$id' : char;
}

/// Width and height of the desktop popover.
const Size _kPopoverSize = Size(432, 448);

/// Shows the emoji picker and resolves to the chosen [EmojiPick], or null if
/// dismissed. On desktop it pops out beside the click that opened it (above
/// the composer's emoji button, like other chat apps); on touch layouts it is
/// a bottom sheet. Pass [spaceId] to surface that space's custom emoji (and
/// to record recents); standard unicode emoji are always available.
Future<EmojiPick?> showAccordEmojiPicker(
  BuildContext context, {
  String? spaceId,
}) {
  final anchor = shouldUseDesktopLayout(context) ? recentPointerAnchor() : null;
  if (anchor == null) {
    return showModalBottomSheet<EmojiPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmojiPickerSheet(spaceId: spaceId),
    );
  }
  final colors = BonfireThemeExtension.of(context);
  return showGeneralDialog<EmojiPick>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close emoji picker',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, _) => CustomSingleChildLayout(
      delegate: _EmojiPopoverLayout(anchor),
      child: Material(
        color: colors.background,
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: SizedBox.fromSize(
          size: _kPopoverSize,
          child: EmojiPickerPanel(
            spaceId: spaceId,
            autofocusSearch: true,
            onPick: (pick) => Navigator.of(ctx).pop(pick),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Places the panel above [anchor] with its right edge at the click (the
/// emoji button sits at the composer's right end), falling back to below it
/// or to the left when there is no room, always kept on screen.
class _EmojiPopoverLayout extends SingleChildLayoutDelegate {
  const _EmojiPopoverLayout(this.anchor);

  final Offset anchor;
  static const double _margin = 12;
  static const double _gap = 10;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          _kPopoverSize.width.clamp(0, constraints.maxWidth - 2 * _margin),
          _kPopoverSize.height.clamp(0, constraints.maxHeight - 2 * _margin),
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.dx + 20 - childSize.width;
    x = x.clamp(
      _margin,
      (size.width - childSize.width - _margin).clamp(_margin, size.width),
    );
    var y = anchor.dy - 24 - _gap - childSize.height;
    if (y < _margin) y = anchor.dy + 24 + _gap;
    y = y.clamp(
      _margin,
      (size.height - childSize.height - _margin).clamp(_margin, size.height),
    );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_EmojiPopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

/// The touch layout: the panel in a bottom sheet with a drag handle.
class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet({this.spaceId});

  final String? spaceId;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.gray,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: EmojiPickerPanel(
                spaceId: spaceId,
                compact: true,
                onPick: (pick) => Navigator.of(context).pop(pick),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
