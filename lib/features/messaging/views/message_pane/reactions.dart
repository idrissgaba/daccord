part of 'message_pane.dart';

/// Opens the full emoji picker to add a reaction to the message.
class _ReactButton extends StatelessWidget {
  const _ReactButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return IconButton(
      tooltip: 'Add reaction',
      onPressed: onPressed,
      icon: Icon(Icons.add_reaction_outlined, size: 18, color: colors.gray),
    );
  }
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.reaction,
    required this.onTap,
    required this.onShowReactors,
    this.imageUrl,
    this.trustedMediaBaseUrl,
    this.superReaction = false,
  });

  final AccordReaction reaction;

  /// Drawn as a super reaction: a glowing gradient border and a sparkle.
  final bool superReaction;
  final VoidCallback onTap;

  /// Long-press / right-click: reveal who reacted.
  final VoidCallback onShowReactors;

  /// Resolved image URL for a custom-emoji reaction; null for unicode.
  final String? imageUrl;
  final String? trustedMediaBaseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    final rawName = reaction.emoji['name']?.toString() ?? '';
    final rawId = reaction.emoji['id']?.toString();
    // A custom emoji whose source didn't split it arrives as name=`name:id`,
    // id=null; recover the id so we render the image instead of literal text.
    final parsed = parseEmojiToken(rawName);
    final id = rawId ?? parsed.id;
    final name = rawId != null ? rawName : parsed.name;
    final mine = reaction.includesMe;
    return Material(
      color: mine ? colors.primary.withValues(alpha: 0.25) : colors.darkGray,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onShowReactors,
        onSecondaryTap: onShowReactors,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: superReaction
                  ? superReactionColor(colors)
                  : (mine ? colors.primary : Colors.transparent),
              width: superReaction ? 1.5 : 1,
            ),
            boxShadow: superReaction
                ? [
                    BoxShadow(
                      color: superReactionColor(
                        colors,
                      ).withValues(alpha: mine ? 0.55 : 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (superReaction) ...[
                Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: superReactionColor(colors),
                  semanticLabel: 'Super reaction',
                ),
                const SizedBox(width: 3),
              ],
              if (id != null && imageUrl != null)
                MessageMediaGate(
                  source: imageUrl,
                  trustedBaseUrl: trustedMediaBaseUrl,
                  allowExternalConsent: false,
                  blockedPlaceholder: Text(
                    name,
                    style: const TextStyle(fontSize: 14),
                  ),
                  builder: (_, safeUrl) => CachedNetworkImage(
                    imageUrl: safeUrl,
                    width: 16,
                    height: 16,
                    fit: BoxFit.contain,
                    errorWidget: (_, _, _) =>
                        Text(name, style: const TextStyle(fontSize: 14)),
                  ),
                )
              else
                // Unicode reaction: `name` is the shortcode (e.g. `hamburger`),
                // not the glyph — resolve it to the actual emoji character.
                Text(
                  resolveEmojiGlyph(name),
                  style: const TextStyle(fontSize: 16),
                ),
              const SizedBox(width: 4),
              Text(
                '${reaction.count}',
                style: theme.textTheme.labelMedium!.copyWith(
                  color: colors.dirtyWhite,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A popup listing the users who reacted with a given emoji, lazy-loaded when
/// opened (reactor lists aren't prefetched per message). Ports the reference
/// client's reactor reveal.
class _ReactorsDialog extends ConsumerStatefulWidget {
  const _ReactorsDialog({
    required this.channelId,
    required this.messageId,
    required this.emojiName,
    required this.emojiId,
  });

  final String channelId;
  final String messageId;
  final String emojiName;
  final String? emojiId;

  @override
  ConsumerState<_ReactorsDialog> createState() => _ReactorsDialogState();
}

class _ReactorsDialogState extends ConsumerState<_ReactorsDialog> {
  List<AccordUser>? _users;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = ref.accordClient;
    if (client == null) {
      setState(() => _users = const []);
      return;
    }
    final users = await ref
        .read(
          accordMessagesControllerProvider(
            ref.readActiveServerKey() ?? '',
            widget.channelId,
          ).notifier,
        )
        .reactionUsers(
          client,
          widget.messageId,
          widget.emojiName,
          emojiId: widget.emojiId,
        );
    if (mounted) setState(() => _users = users);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final cdnUrl = ref.watchCdnUrl();
    final users = _users;
    return AlertDialog(
      title: Text(
        widget.emojiId == null
            ? 'Reacted with ${resolveEmojiGlyph(widget.emojiName)}'
            : 'Reacted with :${widget.emojiName}:',
      ),
      content: SizedBox(
        width: 300,
        child: users == null
            ? const SizedBox(height: 80, child: LoadingView())
            : users.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No one yet.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: colors.gray),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final user in users)
                    _ReactorTile(user: user, cdnUrl: cdnUrl),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ReactorTile extends StatelessWidget {
  const _ReactorTile({required this.user, required this.cdnUrl});

  final AccordUser user;
  final String? cdnUrl;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = accordAvatarUrl(user, cdnUrl);
    return ListTile(
      dense: true,
      leading: AccordMemberAvatar(
        avatarUrl: avatarUrl,
        initial: accordInitial(accordUserName(user, fallback: '?')),
        backgroundColor: accordAvatarColor(user, user.id),
        radius: 14,
      ),
      title: Text(
        accordUserName(user, fallback: user.id),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The accent of super reactions.
Color superReactionColor(BonfireThemeExtension colors) =>
    Color.lerp(colors.primary, const Color(0xFFFFC857), 0.5)!;

/// A super reaction pill that bursts (a quick pop) whenever its count grows.
class _SuperReactionPill extends StatefulWidget {
  const _SuperReactionPill({
    super.key,
    required this.superReaction,
    required this.child,
  });

  final AccordSuperReaction superReaction;
  final Widget Function(AccordReaction reaction) child;

  @override
  State<_SuperReactionPill> createState() => _SuperReactionPillState();
}

class _SuperReactionPillState extends State<_SuperReactionPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.45), weight: 35),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.45,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_burst);

  @override
  void initState() {
    super.initState();
    if (widget.superReaction.me) _burst.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _SuperReactionPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.superReaction.count > oldWidget.superReaction.count) {
      _burst.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sup = widget.superReaction;
    final token = parseEmojiToken(sup.emoji);
    final reaction = AccordReaction(
      emoji: {'id': token.id, 'name': token.name},
      count: sup.count,
      includesMe: sup.me,
    );
    return ScaleTransition(scale: _scale, child: widget.child(reaction));
  }
}
