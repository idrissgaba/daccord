part of '../accord_discovery.dart';

/// The directory's error line. Always painted above the results so a failed
/// join (which leaves the listings on screen) still reports itself.
class _DirectoryError extends StatelessWidget {
  const _DirectoryError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 18, color: colors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.red),
          ),
        ),
      ],
    );
  }
}

/// Why an almost-empty public directory is not a broken feature.
class _SparseDirectoryNote extends StatelessWidget {
  const _SparseDirectoryNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: colors.dirtyWhite),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This list is short on purpose',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Only communities that choose to advertise themselves appear in the '
            'public directory. Most Accord communities are private or '
            'self-hosted, so you usually reach them from an invite link, or by '
            'connecting straight to the server they run.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.gray),
          ),
        ],
      ),
    );
  }
}

/// Pinned below the results in every host of [AccordDiscoveryBody]: the two
/// ways into a server that isn't in the directory. Always visible, so an empty
/// or one-line directory is never a dead end.
class _ConnectFooter extends StatelessWidget {
  const _ConnectFooter({required this.onManualConnect});

  final VoidCallback onManualConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = BonfireThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.background)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Not listed here? Any Accord server works.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.gray),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed: onManualConnect,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Connect to a server by URL'),
              ),
              TextButton.icon(
                onPressed: () =>
                    showSelfHostingDialog(context, onConnect: onManualConnect),
                icon: const Icon(Icons.home_work_outlined, size: 18),
                label: const Text('Host your own'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiscoveryRequest {
  const _DiscoveryRequest({
    required this.generation,
    required this.masterUrl,
    required this.query,
    required this.tag,
  });

  final int generation;
  final String masterUrl;
  final String query;
  final String? tag;
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.listing,
    required this.colors,
    required this.theme,
    required this.joining,
    required this.onJoin,
  });

  final Map<String, dynamic> listing;
  final BonfireThemeExtension colors;
  final ThemeData theme;
  final bool joining;
  final VoidCallback onJoin;

  /// Prefixes relative icon paths (`/...`) with the listing's own server URL.
  String? get _iconUrl {
    final raw = listing['icon_url']?.toString();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    final server = listing['server_url']?.toString() ?? '';
    if (server.isEmpty) return null;
    final base = AccordServer.normalizeBaseUrl(server);
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  @override
  Widget build(BuildContext context) {
    final name = listing['name']?.toString() ?? 'Unknown Space';
    final description = listing['description']?.toString() ?? '';
    final memberCount = (listing['member_count'] as num?)?.toInt() ?? 0;
    final presenceCount = (listing['presence_count'] as num?)?.toInt() ?? 0;
    final tags = [
      for (final t in (listing['tags'] as List? ?? const []))
        t.toString().trim(),
    ].where((t) => t.isNotEmpty).toList();
    final iconUrl = _iconUrl;

    final memberLine = StringBuffer('$memberCount members');
    if (presenceCount > 0) memberLine.write(' · $presenceCount online');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TickerAwareCircleAvatar(
              radius: 24,
              backgroundColor: colors.darkGray,
              foregroundImage: iconUrl == null
                  ? null
                  : CachedNetworkImageProvider(iconUrl),
              child: Text(
                accordInitial(name),
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    memberLine.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.gray,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final tag in tags.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.darkGray,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              tag,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.gray,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: joining ? null : onJoin,
              child: joining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}
