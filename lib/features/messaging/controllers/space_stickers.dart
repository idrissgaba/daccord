import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'space_stickers.g.dart';

/// A space's stickers. Self-loads the first time it's watched and is kept in
/// sync by `sticker.*` gateway events. `null` means "not loaded yet".
@Riverpod(keepAlive: true)
class SpaceStickersController extends _$SpaceStickersController {
  @override
  List<AccordSticker>? build(String serverKey, String spaceId) {
    final client = ref.watchAccordClientFor(serverKey);
    if (client != null) unawaited(_load(client));
    return null;
  }

  Future<void> _load(AccordClient client) async {
    final stickers = (await client.stickers.list(
      spaceId,
    )).listOrLog<AccordSticker>('stickers for $spaceId');
    if (!ref.mounted || !ref.isCurrentAccordClient(serverKey, client)) return;
    state = stickers ?? const [];
  }

  void upsert(AccordSticker sticker) {
    final current = state ?? const <AccordSticker>[];
    final index = current.indexWhere((s) => s.id == sticker.id);
    if (index < 0) {
      state = [...current, sticker];
    } else {
      state = [...current]..[index] = sticker;
    }
  }

  void remove(String stickerId) {
    final current = state;
    if (current == null) return;
    state = current.where((s) => s.id != stickerId).toList();
  }
}
