import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/controllers/space_stickers.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/shared/utils/client_access.dart';
import 'package:bonfire/shared/utils/confirm_dialog.dart';
import 'package:bonfire/shared/utils/responsive_dialog.dart';
import 'package:bonfire/shared/utils/rest_result_ext.dart';
import 'package:bonfire/shared/utils/text_prompt_dialog.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The absolute URL of a sticker's image, or null for a deleted sticker.
String? stickerUrl(AccordSticker sticker, String? cdnUrl) {
  final image = sticker.image;
  if (image == null || image.isEmpty) return null;
  return AccordCDN.resolvePath(image, cdnUrl: cdnUrl ?? '');
}

/// A sticker as a message shows it: up to 160 px, or its name once deleted.
class MessageSticker extends ConsumerWidget {
  const MessageSticker({super.key, required this.sticker});

  final AccordSticker sticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = stickerUrl(sticker, ref.watchCdnUrl());
    final colors = BonfireThemeExtension.of(context);
    return Padding(
      key: ValueKey('message-sticker-${sticker.id}'),
      padding: const EdgeInsets.only(top: 4),
      child: Tooltip(
        message: sticker.name,
        child: url == null
            ? Text('🏷️ ${sticker.name}', style: TextStyle(color: colors.gray))
            : CachedNetworkImage(
                imageUrl: url,
                width: 160,
                height: 160,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                errorWidget: (_, _, _) => Text('🏷️ ${sticker.name}'),
              ),
      ),
    );
  }
}

/// Picks a sticker from the spaces the user belongs to, [spaceId]'s first.
Future<AccordSticker?> showStickerPicker(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<AccordSticker>(
    context: context,
    builder: (_) => StickerPickerDialog(spaceId: spaceId),
  );
}

class StickerPickerDialog extends ConsumerWidget {
  const StickerPickerDialog({super.key, required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = [...?ref.watch(spacesControllerProvider)]
      ..sort((a, b) => a.id == spaceId ? -1 : (b.id == spaceId ? 1 : 0));
    if (spaces.isEmpty) return const SizedBox.shrink();
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 520, maxHeight: 520),
        child: DefaultTabController(
          length: spaces.length,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                isScrollable: true,
                tabs: [for (final space in spaces) Tab(text: space.name)],
              ),
              Flexible(
                child: SizedBox(
                  height: 380,
                  child: TabBarView(
                    children: [
                      for (final space in spaces)
                        _StickerGrid(spaceId: space.id),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerGrid extends ConsumerWidget {
  const _StickerGrid({required this.spaceId});

  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stickers = ref.watch(
      spaceStickersControllerProvider(
        ref.watchActiveServerKey() ?? '',
        spaceId,
      ),
    );
    final cdnUrl = ref.watchCdnUrl();
    if (stickers == null) return const LoadingView();
    if (stickers.isEmpty) {
      return const Center(child: Text('No stickers in this space yet.'));
    }
    return GridView.count(
      crossAxisCount: 4,
      padding: const EdgeInsets.all(12),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: [
        for (final sticker in stickers)
          Tooltip(
            message: sticker.name,
            child: InkWell(
              key: ValueKey('sticker-${sticker.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.of(context).pop(sticker),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: stickerUrl(sticker, cdnUrl) == null
                    ? Center(child: Text(sticker.name))
                    : CachedNetworkImage(
                        imageUrl: stickerUrl(sticker, cdnUrl)!,
                        fit: BoxFit.contain,
                        errorWidget: (_, _, _) =>
                            Center(child: Text(sticker.name)),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Upload, rename and delete a space's stickers (needs `manage_emojis`).
Future<void> showStickerManagement(
  BuildContext context, {
  required String spaceId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => StickerManagementDialog(spaceId: spaceId),
  );
}

class StickerManagementDialog extends ConsumerStatefulWidget {
  const StickerManagementDialog({super.key, required this.spaceId});

  final String spaceId;

  @override
  ConsumerState<StickerManagementDialog> createState() =>
      _StickerManagementDialogState();
}

class _StickerManagementDialogState
    extends ConsumerState<StickerManagementDialog> {
  bool _busy = false;
  String? _error;

  SpaceStickersController get _controller => ref.read(
    spaceStickersControllerProvider(
      ref.readActiveServerKey() ?? '',
      widget.spaceId,
    ).notifier,
  );

  Future<void> _run(
    Future<RestResult> Function(AccordClient client) action,
    String failure,
    void Function(Object? data) onDone,
  ) async {
    final client = ref.accordClient;
    if (client == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action(client);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!result.ok) _error = result.errorMessageOr(failure);
    });
    if (result.ok) onDone(result.data);
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'gif', 'webp'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    if (file?.bytes == null || !mounted) return;
    final base = file!.name.split('.').first.replaceAll(RegExp(r'[_-]+'), ' ');
    final name = base.trim().length >= 2 ? base.trim() : 'Sticker';
    await _run(
      (client) => client.stickers.create(
        widget.spaceId,
        name: name.length > 30 ? name.substring(0, 30) : name,
        image: AccordCDN.buildDataUri(file.bytes!, file.name),
      ),
      'Could not upload the sticker',
      (data) {
        if (data is AccordSticker) _controller.upsert(data);
      },
    );
  }

  Future<void> _rename(AccordSticker sticker) async {
    final name = (await showTextPromptDialog(
      context,
      title: 'Rename sticker',
      label: 'Name',
      helperText: '2–30 characters',
      initial: sticker.name,
    ))?.trim();
    if (name == null || name == sticker.name) return;
    await _run(
      (client) =>
          client.stickers.update(widget.spaceId, sticker.id, name: name),
      'Could not rename the sticker',
      (data) {
        if (data is AccordSticker) _controller.upsert(data);
      },
    );
  }

  Future<void> _delete(AccordSticker sticker) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete ${sticker.name}?',
      message: 'Messages that used it will show its name instead.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (ok != true || !mounted) return;
    await _run(
      (client) => client.stickers.delete(widget.spaceId, sticker.id),
      'Could not delete the sticker',
      (_) => _controller.remove(sticker.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final stickers = ref.watch(
      spaceStickersControllerProvider(
        ref.watchActiveServerKey() ?? '',
        widget.spaceId,
      ),
    );
    final cdnUrl = ref.watchCdnUrl();
    return Dialog(
      child: ConstrainedBox(
        constraints: dialogConstraints(context, maxWidth: 480, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.sticky_note_2_outlined,
                    size: 18,
                    color: colors.dirtyWhite,
                  ),
                  const SizedBox(width: 8),
                  Text('Stickers', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              Text(
                'PNG, GIF or WebP, up to 60 per space.',
                style: theme.textTheme.bodySmall!.copyWith(color: colors.gray),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('sticker-upload'),
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload, size: 18),
                label: const Text('Upload sticker'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                InlineError(_error!, centered: false),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: stickers == null
                    ? const LoadingView()
                    : stickers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('No stickers yet.')),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: stickers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final sticker = stickers[index];
                          final url = stickerUrl(sticker, cdnUrl);
                          return ListTile(
                            key: ValueKey('manage-sticker-${sticker.id}'),
                            leading: url == null
                                ? const Icon(Icons.image_outlined)
                                : CachedNetworkImage(
                                    imageUrl: url,
                                    width: 40,
                                    height: 40,
                                    errorWidget: (_, _, _) =>
                                        const Icon(Icons.broken_image),
                                  ),
                            title: Text(sticker.name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Rename',
                                  onPressed: _busy
                                      ? null
                                      : () => _rename(sticker),
                                  icon: const Icon(Icons.edit, size: 18),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: _busy
                                      ? null
                                      : () => _delete(sticker),
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: colors.red,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
