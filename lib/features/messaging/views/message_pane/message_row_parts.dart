part of 'message_pane.dart';

/// The row's sub-trees: thread chip, reactions, reply preview, attachments. Split from [_MessageRowState] for size.
mixin _MessageRowParts
    on ConsumerState<_MessageRow>, _MessageRowEditing, _MessageRowHandlers {
  Widget _buildThreadChip(
    AccordMessage message,
    ThemeData theme,
    BonfireThemeExtension colors,
  ) {
    final count = message.replyCount;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _openThread(message),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                '$count ${count == 1 ? 'reply' : 'replies'}',
                style: theme.textTheme.labelMedium!.copyWith(
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactions(
    AccordMessage message,
    ThemeData theme,
    BonfireThemeExtension colors,
    String? cdnUrl,
  ) {
    final messageId = message.id;
    final spaceId = widget.spaceId;
    final customEmoji = spaceId == null
        ? const <AccordEmoji>[]
        : ref.watch(
                accordEmojisControllerProvider(
                  ref.readActiveServerKey() ?? '',
                  spaceId,
                ),
              ) ??
              const <AccordEmoji>[];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final sup in message.superReactions)
            _SuperReactionPill(
              key: ValueKey('super-${sup.emoji}'),
              superReaction: sup,
              child: (reaction) => _ReactionPill(
                reaction: reaction,
                superReaction: true,
                imageUrl: _reactionEmojiUrl(reaction, customEmoji, cdnUrl),
                trustedMediaBaseUrl: cdnUrl,
                onTap: () => _toggleSuperReaction(messageId, sup.emoji),
                onShowReactors: () =>
                    _toggleSuperReaction(messageId, sup.emoji),
              ),
            ),
          for (final reaction in message.reactions ?? const <AccordReaction>[])
            _ReactionPill(
              reaction: reaction,
              imageUrl: _reactionEmojiUrl(reaction, customEmoji, cdnUrl),
              trustedMediaBaseUrl: cdnUrl,
              onTap: () => _toggleReaction(
                messageId,
                reaction.emoji['name']?.toString() ?? '',
                emojiId: reaction.emoji['id']?.toString(),
              ),
              onShowReactors: () => _showReactors(messageId, reaction),
            ),
        ],
      ),
    );
  }

  /// Resolves a custom reaction's image URL. Reactions only carry `{id, name}`,
  /// so the emoji is looked up from the space's catalog by id and resolved via
  /// the shared, federation-aware [accordEmojiUrl] (remote emoji resolve
  /// against their home CDN, as in message markup). A *qualified* id missing
  /// from the catalog resolves to nothing rather than the local CDN, because
  /// stripping its domain would request an unrelated local emoji with the same
  /// local id. Null for unicode reactions.
  String? _reactionEmojiUrl(
    AccordReaction reaction,
    List<AccordEmoji> customEmoji,
    String? cdnUrl,
  ) {
    final rawId = reaction.emoji['id']?.toString();
    final id =
        rawId ?? parseEmojiToken(reaction.emoji['name']?.toString() ?? '').id;
    if (id == null) return null;
    final match = customEmoji.firstWhereOrNull((e) => e.id == id);
    if (match == null && isRemoteId(id)) return null;
    return accordEmojiUrl(match ?? AccordEmoji(id: id), cdnUrl);
  }

  /// A compact "↩ Name preview" line above a reply message, resolving the
  /// referenced message from the loaded channel cache when available.
  Widget _buildReplyPreview(
    AccordMessage message,
    BonfireThemeExtension colors,
  ) {
    final theme = Theme.of(context);
    final referenced = widget.messagesById[message.replyTo];
    String name = 'Unknown';
    String preview = '';
    if (referenced != null) {
      // Same resolution order as the row header: member nickname → on-demand
      // user cache → "Unknown" while the fetch lands. Never the raw snowflake.
      final authorId = referenced.authorId;
      final member = widget.spaceId == null
          ? null
          : ref.watch(
              accordMembersControllerProvider(
                ref.readActiveServerKey() ?? '',
                widget.spaceId!,
              ).select((m) => m?[authorId]),
            );
      final user = ref.watch(
        accordUsersControllerProvider(
          ref.readActiveServerKey() ?? '',
        ).select((u) => u[authorId]),
      );
      name = accordAuthorNameOf(
        authorId,
        member: member,
        user: user,
        ensure: ref
            .read(
              accordUsersControllerProvider(
                ref.readActiveServerKey() ?? '',
              ).notifier,
            )
            .ensure,
      );
      final content = plainMessagePreview(
        accordMessageText(referenced, authorName: name),
      );
      preview = content.isEmpty ? '(attachment)' : content;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 2),
      child: Row(
        children: [
          Icon(Icons.reply, size: 12, color: colors.gray),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              preview.isEmpty ? name : '$name  $preview',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium!.copyWith(color: colors.gray),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders one attachment inline: tappable image (→ lightbox), video player,
  /// audio player, or a filename chip for other types.
  Widget _buildAttachment(
    AccordAttachment attachment,
    String? cdnUrl,
    ThemeData theme,
  ) {
    if (attachment.encryption != null) {
      final client = ref.accordClient;
      if (client != null && client.encryption != null) {
        return EncryptedAttachment(attachment: attachment, client: client);
      }
      return const Text('Encrypted attachment unavailable.');
    }
    final url = _attachmentUrl(attachment, cdnUrl);
    switch (_previewOf(attachment)) {
      case AttachmentPreview.image:
        return MessageMediaGate(
          source: attachment.url,
          trustedBaseUrl: cdnUrl,
          builder: (_, safeUrl) => MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => showImageLightbox(
                context,
                safeUrl,
                attachmentId: attachmentKey(attachment),
              ),
              child: _ImageAttachment(
                url: safeUrl,
                width: _asDouble(attachment.width),
                height: _asDouble(attachment.height),
              ),
            ),
          ),
        );
      case AttachmentPreview.video:
        return InlineVideoPlayer(
          url: url,
          filename: attachment.filename,
          width: _asDouble(attachment.width),
          height: _asDouble(attachment.height),
        );
      case AttachmentPreview.audio:
        return InlineAudioPlayer(url: url, filename: attachment.filename);
      case AttachmentPreview.none:
        return Text(
          '📎 ${attachment.filename}',
          style: theme.textTheme.bodyMedium,
        );
    }
  }
}
