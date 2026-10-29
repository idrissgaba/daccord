part of '../emoji_picker.dart';

/// A pseudo-category selected by the rail in addition to the standard
/// [EmojiCategory] values.
enum _Tab { recent, custom }

/// Size of one emoji cell; the grid math in [_Section] relies on it.
const double _kCell = 40;
const double _kHeader = 28;

/// Skin-tone modifiers, so a toned recent/reaction glyph can be traced back
/// to its catalogue entry.
const _kToneModifiers = ['🏻', '🏼', '🏽', '🏾', '🏿'];

/// The emoji picker's content: search, skin tone, a category rail, one grid
/// scrolling through every section, and a preview bar naming the hovered
/// emoji. Shared by the desktop popover and the touch bottom sheet.
class EmojiPickerPanel extends ConsumerStatefulWidget {
  const EmojiPickerPanel({
    super.key,
    required this.onPick,
    this.spaceId,
    this.compact = false,
    this.autofocusSearch = false,
  });

  final ValueChanged<EmojiPick> onPick;
  final String? spaceId;

  /// Touch layout: the category rail runs horizontally above the grid.
  final bool compact;
  final bool autofocusSearch;

  @override
  ConsumerState<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends ConsumerState<EmojiPickerPanel> {
  final _searchController = TextEditingController();
  final _scroll = ScrollController();
  final _hovered = ValueNotifier<EmojiPick?>(null);
  String _query = '';

  /// The rail entry highlighted: follows the scroll position, or the search.
  Object _active = EmojiCategory.smileys;
  List<_Section> _sections = const [];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_followScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    _hovered.dispose();
    super.dispose();
  }

  String? get _cdnUrl => ref.readCdnUrl();

  List<AccordEmoji> get _customEmoji {
    final spaceId = widget.spaceId;
    if (spaceId == null) return const [];
    return ref.watch(
          accordEmojisControllerProvider(
            ref.readActiveServerKey() ?? '',
            spaceId,
          ),
        ) ??
        const [];
  }

  int get _tone =>
      ref.watch(settingsControllerProvider.select((s) => s.emojiSkinTone));

  void _pick(EmojiPick pick) {
    if (widget.spaceId != null) {
      ref
          .read(settingsControllerProvider.notifier)
          .addRecentEmoji(pick.recentToken);
    }
    widget.onPick(pick);
  }

  void _followScroll() {
    if (!_scroll.hasClients || _query.isNotEmpty) return;
    final offset = _scroll.offset + 1;
    Object? current;
    for (final s in _sections) {
      if (s.start <= offset) current = s.id;
    }
    if (current != null && current != _active) {
      setState(() => _active = current!);
    }
  }

  void _jumpTo(Object id) {
    if (_query.isNotEmpty) {
      _searchController.clear();
      _query = '';
    }
    setState(() => _active = id);
    final section = _sections.where((s) => s.id == id).firstOrNull;
    if (section == null || !_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    _scroll.animateTo(
      section.start.clamp(0, max),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  /// Reconstructs an [EmojiPick] from a stored recent token, resolving custom
  /// tokens (`name:id`) against the current space's emoji.
  EmojiPick? _pickFromRecent(String token, List<AccordEmoji> custom) {
    final sep = token.lastIndexOf(':');
    if (sep > 0 && sep < token.length - 1) {
      final id = token.substring(sep + 1);
      final match = custom.firstWhere(
        (e) => e.id == id,
        orElse: () => AccordEmoji(),
      );
      if (match.id == null) return null; // custom emoji no longer available
      return EmojiPick(
        name: match.name,
        id: match.id,
        imageUrl: _emojiImageUrl(match),
      );
    }
    var base = token;
    for (final m in _kToneModifiers) {
      base = base.replaceAll(m, '');
    }
    final entry = kEmojiCatalog.firstWhere(
      (e) => e.char == token || e.char == base,
      orElse: () => EmojiEntry(token, token, EmojiCategory.smileys),
    );
    return EmojiPick(name: entry.name, char: token);
  }

  String? _emojiImageUrl(AccordEmoji emoji) => accordEmojiUrl(emoji, _cdnUrl);

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final custom = _customEmoji;
    final recents = ref.watch(
      settingsControllerProvider.select((s) => s.recentEmoji),
    );
    final tone = _tone;
    final rail = _CategoryRail(
      hasCustom: custom.isNotEmpty,
      hasRecent: recents.isNotEmpty,
      selected: _query.isEmpty ? _active : null,
      horizontal: widget.compact,
      onSelect: _jumpTo,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('emoji-picker-search'),
                  controller: _searchController,
                  autofocus: widget.autofocusSearch,
                  style: Theme.of(context).textTheme.bodyMedium,
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                  onSubmitted: (_) => _pickFirstResult(custom, tone),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: colors.darkGray,
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: colors.gray,
                    ),
                    hintText: 'Find the perfect emoji',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SkinToneButton(
                tone: tone,
                onChanged: (t) => ref
                    .read(settingsControllerProvider.notifier)
                    .setEmojiSkinTone(t),
              ),
            ],
          ),
        ),
        if (widget.compact) rail,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.compact) rail,
              Expanded(
                child: _query.isNotEmpty
                    ? _buildSearchGrid(colors, custom, tone)
                    : _buildSections(colors, custom, recents, tone),
              ),
            ],
          ),
        ),
        _PreviewBar(hovered: _hovered),
      ],
    );
  }

  List<EmojiEntry> _unicodeHits() => [
    for (final e in kEmojiCatalog)
      if (e.matches(_query)) e,
  ];

  List<AccordEmoji> _customHits(List<AccordEmoji> custom) => [
    for (final e in custom)
      if (e.name.toLowerCase().contains(_query)) e,
  ];

  void _pickFirstResult(List<AccordEmoji> custom, int tone) {
    if (_query.isEmpty) return;
    final customHits = _customHits(custom);
    if (customHits.isNotEmpty) {
      final e = customHits.first;
      _pick(EmojiPick(name: e.name, id: e.id, imageUrl: _emojiImageUrl(e)));
      return;
    }
    final hits = _unicodeHits();
    if (hits.isNotEmpty) _pick(_unicodePick(hits.first, tone));
  }

  Widget _buildSearchGrid(
    BonfireThemeExtension colors,
    List<AccordEmoji> custom,
    int tone,
  ) {
    final unicodeHits = _unicodeHits();
    final customHits = _customHits(custom);
    if (unicodeHits.isEmpty && customHits.isEmpty) {
      return _empty(colors, 'No emoji match "$_query"');
    }
    final cells = [
      for (final e in customHits) _customCell(e),
      for (final e in unicodeHits) _unicodeCell(e, tone),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _columns(constraints.maxWidth),
          mainAxisExtent: _kCell,
        ),
        itemCount: cells.length,
        itemBuilder: (context, i) => cells[i],
      ),
    );
  }

  int _columns(double width) => ((width - 16) / _kCell).floor().clamp(1, 20);

  Widget _buildSections(
    BonfireThemeExtension colors,
    List<AccordEmoji> custom,
    List<String> recents,
    int tone,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columns(constraints.maxWidth);
        final sections = <_Section>[];
        var offset = 0.0;
        void add(Object id, String title, List<Widget> cells) {
          if (cells.isEmpty) return;
          final rows = (cells.length / columns).ceil();
          final height = _kHeader + rows * _kCell;
          sections.add(_Section(id, title, cells, offset));
          offset += height;
        }

        final recentPicks = [
          for (final token in recents)
            if (_pickFromRecent(token, custom) case final p?) p,
        ];
        add(_Tab.recent, 'Frequently used', [
          for (final p in recentPicks) _pickCell(p),
        ]);
        add(_Tab.custom, 'Custom', [for (final e in custom) _customCell(e)]);
        for (final category in EmojiCategory.values) {
          add(category, category.label, [
            for (final e in kEmojiCatalog)
              if (e.category == category) _unicodeCell(e, tone),
          ]);
        }
        _sections = sections;
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            for (final s in sections) ...[
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _kHeader,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Text(
                      s.title.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: colors.gray,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: _kCell,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => s.cells[i],
                    childCount: s.cells.length,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        );
      },
    );
  }

  Widget _empty(BonfireThemeExtension colors, String message) {
    return Center(
      child: Text(message, style: TextStyle(color: colors.gray)),
    );
  }

  EmojiPick _unicodePick(EmojiEntry entry, int tone) =>
      EmojiPick(name: entry.name, char: entry.withTone(tone));

  Widget _unicodeCell(EmojiEntry entry, int tone) {
    final pick = _unicodePick(entry, tone);
    return _cell(
      pick: pick,
      child: Text(pick.char, style: const TextStyle(fontSize: 26)),
    );
  }

  Widget _customCell(AccordEmoji emoji) {
    final url = _emojiImageUrl(emoji);
    return _pickCell(EmojiPick(name: emoji.name, id: emoji.id, imageUrl: url));
  }

  Widget _pickCell(EmojiPick pick) {
    return _cell(
      pick: pick,
      child: pick.isCustom
          ? (pick.imageUrl == null
                ? Text(':${pick.name}:', style: const TextStyle(fontSize: 9))
                : MessageMediaGate(
                    source: pick.imageUrl,
                    trustedBaseUrl: _cdnUrl,
                    allowExternalConsent: false,
                    blockedPlaceholder: Text(
                      ':${pick.name}:',
                      style: const TextStyle(fontSize: 9),
                    ),
                    builder: (_, safeUrl) => CachedNetworkImage(
                      imageUrl: safeUrl,
                      width: 26,
                      height: 26,
                      fit: BoxFit.contain,
                    ),
                  ))
          : Text(pick.char, style: const TextStyle(fontSize: 26)),
    );
  }

  Widget _cell({required EmojiPick pick, required Widget child}) {
    return MouseRegion(
      onEnter: (_) => _hovered.value = pick,
      onExit: (_) {
        if (_hovered.value == pick) _hovered.value = null;
      },
      // The preview bar names the hovered emoji; the tooltip is for screen
      // readers and tests, so it waits long enough not to double up.
      child: Tooltip(
        message: pick.name,
        waitDuration: const Duration(seconds: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _pick(pick),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// One category block of the continuous grid and where it starts, in
/// scroll offset, for the rail to jump to and to follow.
class _Section {
  const _Section(this.id, this.title, this.cells, this.start);

  final Object id;
  final String title;
  final List<Widget> cells;
  final double start;
}

/// The category selector: Recent and Custom (when populated) plus the nine
/// standard unicode categories, as a vertical rail on desktop and a
/// horizontal strip on touch layouts.
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.hasCustom,
    required this.hasRecent,
    required this.selected,
    required this.horizontal,
    required this.onSelect,
  });

  final bool hasCustom;
  final bool hasRecent;
  final Object? selected;
  final bool horizontal;
  final ValueChanged<Object> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    final tabs = <Widget>[
      if (hasRecent)
        _tab(colors, _Tab.recent, Icons.history, 'Frequently used'),
      if (hasCustom)
        _tab(colors, _Tab.custom, Icons.workspace_premium_outlined, 'Custom'),
      for (final c in EmojiCategory.values) _tab(colors, c, c.icon, c.label),
    ];
    if (horizontal) {
      return SizedBox(
        height: 40,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: HorizontalWheelScroll(
            builder: (context, controller) => ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: tabs,
            ),
          ),
        ),
      );
    }
    return Container(
      width: 44,
      color: colors.foreground,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: tabs,
      ),
    );
  }

  Widget _tab(
    BonfireThemeExtension colors,
    Object value,
    IconData icon,
    String label,
  ) {
    final active = selected == value;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: active ? colors.darkGray : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: IconButton(
          onPressed: () => onSelect(value),
          visualDensity: VisualDensity.compact,
          icon: Icon(
            icon,
            size: 20,
            color: active ? colors.dirtyWhite : colors.gray,
          ),
        ),
      ),
    );
  }
}

/// The hovered emoji, large, with its `:name:` — or a hint when nothing is
/// hovered — along the bottom of the panel.
class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.hovered});

  final ValueNotifier<EmojiPick?> hovered;

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return Container(
      height: 44,
      color: colors.foreground,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ValueListenableBuilder<EmojiPick?>(
        valueListenable: hovered,
        builder: (context, pick, _) {
          if (pick == null) {
            return Row(
              children: [
                Icon(Icons.emoji_emotions_outlined, color: colors.gray),
                const SizedBox(width: 10),
                Text(
                  'Pick an emoji',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: colors.gray),
                ),
              ],
            );
          }
          return Row(
            children: [
              if (pick.isCustom && pick.imageUrl != null)
                CachedNetworkImage(
                  imageUrl: pick.imageUrl!,
                  width: 28,
                  height: 28,
                  fit: BoxFit.contain,
                )
              else
                Text(pick.char, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ':${pick.name}:',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: colors.dirtyWhite,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The skin-tone chooser: a hand in the current tone that opens the six
/// options.
class _SkinToneButton extends StatelessWidget {
  const _SkinToneButton({required this.tone, required this.onChanged});

  final int tone;
  final ValueChanged<int> onChanged;

  static const _hand = EmojiEntry(
    '✋',
    'raised_hand',
    EmojiCategory.people,
    '',
    ['✋🏻', '✋🏼', '✋🏽', '✋🏾', '✋🏿'],
  );
  static const _labels = [
    'No skin tone',
    'Light skin tone',
    'Medium-light skin tone',
    'Medium skin tone',
    'Medium-dark skin tone',
    'Dark skin tone',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = BonfireThemeExtension.of(context);
    return PopupMenuButton<int>(
      key: const Key('emoji-skin-tone'),
      tooltip: 'Skin tone',
      color: colors.foreground,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (var t = 0; t <= 5; t++)
          PopupMenuItem<int>(
            value: t,
            height: 36,
            child: Row(
              children: [
                Text(_hand.withTone(t), style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Text(_labels[t]),
                if (t == tone) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 16, color: colors.primary),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.darkGray,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(_hand.withTone(tone), style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}
