import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../addons.dart';
import '../kit/focus.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'title.dart';

(String, String, String) _key(Catalog c) => (c.addon.base, c.type, c.id);
const _favourites = ('', '', 'favourites');

// The client can't tell offline from an addon being down: both are AddonError.unreachable.
bool _offline(Object? e) => e is AddonException && e.kind == AddonError.unreachable;

/// D1: addon catalogs as a poster wall, with search over the current type.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({this.onAddSources, super.key});

  /// The shell can select its Sources destination without opening another route.
  /// Otherwise the app's named Sources route is used.
  final VoidCallback? onAddSources;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _search = TextEditingController();
  final _typeSwitchFocus = FocusNode(debugLabel: 'Discover Movies');
  final _searchActionFocus = FocusNode(debugLabel: 'Discover Search');
  // A one-line field keeps Down for its caret; on TV, Down leaves it towards the results.
  final _searchFieldFocus = FocusNode(
    debugLabel: 'Discover search field',
    onKeyEvent: (node, event) {
      if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
      node.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    },
  );

  // EditableText owns focus while editing. Its non-focusable ancestor paints
  // the same FocusRing as every other TV control, including descendant focus.
  final _searchFrameFocus = FocusNode(
    debugLabel: 'Discover search ring',
    canRequestFocus: false,
    skipTraversal: true,
  );
  // The TV header moves between feeds (catalog, search, favourites) without a remount, so the control just
  // used keeps focus.
  final _header = GlobalKey(debugLabel: 'Discover header');
  bool _searchOpen = false;
  String _type = 'movie', _query = '';
  (String, String, String)? _selected;

  @override
  void dispose() {
    _search.dispose();
    _typeSwitchFocus.dispose();
    _searchActionFocus.dispose();
    _searchFieldFocus.dispose();
    _searchFrameFocus.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    setState(() => _query = '');
  }

  void _pick(VoidCallback change) {
    HapticFeedback.selectionClick();
    setState(change);
  }

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchOpen) _searchFieldFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFieldFocus.unfocus();
    _search.clear();
    setState(() {
      _query = '';
      _searchOpen = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_searchOpen) _searchActionFocus.requestFocus();
    });
  }

  void _addSources() {
    final onAddSources = widget.onAddSources;
    if (onAddSources != null) {
      onAddSources();
    } else {
      Navigator.of(context).pushNamed('/sources');
    }
  }

  Widget _tvHeader(
    List<Catalog> catalogs,
    Catalog? selected,
    bool hasFavourites,
    bool showFavourites,
  ) => Padding(
        padding: const EdgeInsets.only(top: FlickTv.insetV, bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header rows sit [FlickTv.gridPad] in, like the chips and the grid: lined up, and no ring is clipped.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FlickTv.gridPad),
            child: Row(children: [
            Text('Discover', style: FlickTv.page),
            const SizedBox(width: FlickTv.contentGap),
            if (_searchOpen) ...[
              Expanded(
                child: FocusFrame(
                  focusNode: _searchFrameFocus,
                  radius: FlickTokens.controlRadius,
                  onActivate: () {
                    _searchFieldFocus.requestFocus();
                    SystemChannels.textInput.invokeMethod<void>('TextInput.show');
                  },
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFieldFocus,
                    style: FlickTv.body,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) => setState(() {
                      if (v.trim().isEmpty) _query = '';
                    }),
                    // Focus stays in the field after a search; Down enters the results.
                    onEditingComplete: () {},
                    onSubmitted: (q) => setState(() => _query = q.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search titles',
                      hintStyle: FlickTv.body.copyWith(color: FlickTokens.textSecondary),
                      prefixIcon: const Icon(Icons.search),
                      constraints: const BoxConstraints(minHeight: FlickTokens.minTouchTarget),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(FlickTokens.controlRadius)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FlickTv.gridGap),
              FocusFrame.button(
                semanticLabel: 'Close search',
                onActivate: _closeSearch,
                child: const SizedBox(
                  width: FlickTokens.minTouchTarget,
                  height: FlickTokens.minTouchTarget,
                  child: Icon(Icons.close),
                ),
              ),
            ] else ...[
              const Spacer(),
              FocusFrame.button(
                focusNode: _searchActionFocus,
                semanticLabel: 'Search titles',
                onActivate: _openSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.search, size: 22),
                    const SizedBox(width: 8),
                    Text('Search', style: FlickTv.body),
                  ]),
                ),
              ),
            ],
          ])),
          const SizedBox(height: 12),
          // The tab's initial target: entering Discover with nothing remembered lands on Movies.
          InitialFocus(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FlickTv.gridPad),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (type, label) in [('movie', 'Movies'), ('series', 'Series')])
              _TvChoice(
                label,
                selected: _type == type,
                focusNode: type == 'movie' ? _typeSwitchFocus : null,
                onActivate: () {
                  if (_type != type) {
                    _pick(() {
                      _type = type;
                      _selected = null;
                    });
                  }
                },
              ),
          ]))),
          const SizedBox(height: 8),
          // A non-lazy row keeps every catalog reachable by directional focus.
          // Its padding leaves room for the outer ring at the viewport edges.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(FlickTv.gridPad),
            child: Row(children: [
              if (hasFavourites) ...[
                _TvChoice(
                  'Favourites',
                  icon: Icons.favorite_border,
                  selected: showFavourites,
                  onActivate: () {
                    if (!showFavourites) _pick(() => _selected = _favourites);
                  },
                ),
                const SizedBox(width: 8),
              ],
              for (final c in catalogs) ...[
                if (c != catalogs.first) const SizedBox(width: 8),
                _TvChoice(
                  c.name,
                  selected: !showFavourites && c == selected,
                  onActivate: () {
                    if (showFavourites || c != selected) _pick(() => _selected = _key(c));
                  },
                ),
              ],
            ]),
          ),
        ]),
      );

  Widget _buildTv(
    List<Catalog> catalogs,
    Catalog? selected,
    bool hasFavourites,
    bool showFavourites,
    List<MetaPreview> favourites,
    Catalog? searchable,
    bool searching,
    bool heroes,
  ) {
    final header = KeyedSubtree(key: _header, child: _tvHeader(catalogs, selected, hasFavourites, showFavourites));
    final Widget body;
    if (searching && searchable == null) {
      body = _TvDiscoverScroll(
        header: header,
        slivers: [
          SliverToBoxAdapter(
            child: _TvNotice(
              Icons.search,
              "Your sources can't search these titles.",
              action: 'Clear search',
              onAction: _clear,
            ),
          ),
        ],
      );
    } else if (searching) {
      body = CatalogFeed(
        searchable!,
        query: _query,
        onClear: _clear,
        tvHeader: header,
        onAddSources: _addSources,
        key: ValueKey(('tv-search', _key(searchable), _query)),
      );
    } else if (showFavourites) {
      body = CatalogFeed.saved(
        favourites,
        tvHeader: header,
        onAddSources: _addSources,
        key: ValueKey(('tv-saved', favourites.map((f) => f.id).join(','))),
      );
    } else if (selected == null) {
      body = _TvDiscoverScroll(
        header: header,
        slivers: [
          SliverToBoxAdapter(
            child: _TvNotice(
              Icons.video_library_outlined,
              'No catalogs for this type yet.',
              action: 'Add sources',
              onAction: _addSources,
            ),
          ),
        ],
      );
    } else {
      body = CatalogFeed(
        selected,
        tvHeader: header,
        onAddSources: _addSources,
        key: ValueKey(('tv-catalog', _key(selected))),
      );
    }

    // Back with search open closes it before the shell's Back contract: the shell invokes DismissIntent first.
    return Actions(
      actions: {
        if (_searchOpen)
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
            _closeSearch();
            return true;
          }),
      },
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
        child: HeroMode(enabled: heroes, child: body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([addons, saved]),
        builder: (context, _) {
          final catalogs = addons.catalogs.where((c) => c.type == _type).toList();
          final selected = catalogs.where((c) => _key(c) == _selected).firstOrNull ?? catalogs.firstOrNull;
          final favourites = [for (final f in saved.favourites) if (f.type == _type) f];
          final showFavourites = _selected == _favourites && favourites.isNotEmpty;
          final searchable = catalogs.where((c) => c.searchable).firstOrNull;
          final searching = _query.isNotEmpty;
          final heroes = !MediaQuery.disableAnimationsOf(context);
          if (context.tv) {
            return _buildTv(catalogs, selected, favourites.isNotEmpty, showFavourites,
                favourites, searchable, searching, heroes);
          }
          return SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      style: FlickText.body,
                      textInputAction: TextInputAction.search,
                      // Rebuilds for the clear button; an emptied field restores the catalog.
                      onChanged: (v) => setState(() {
                        if (v.trim().isEmpty) _query = '';
                      }),
                      onSubmitted: (q) => setState(() => _query = q.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search titles',
                        prefixIcon: const Icon(Icons.search),
                        constraints: const BoxConstraints(minHeight: 56),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(tooltip: 'Clear search', onPressed: _clear, icon: const Icon(Icons.close)),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
                child: Row(children: [
                  for (final (type, label) in [('movie', 'Movies'), ('series', 'Series')])
                    Expanded(
                      child: _Segment(
                        label,
                        selected: _type == type,
                        onTap: () => _pick(() {
                          _type = type;
                          _selected = null;
                        }),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
                child: Row(children: [
                  if (favourites.isNotEmpty) ...[
                    ChoiceChip(
                      avatar: const Icon(Icons.favorite_rounded),
                      label: const Text('Favourites'),
                      selected: showFavourites,
                      showCheckmark: false,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) {
                        if (!showFavourites) _pick(() => _selected = _favourites);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                  for (final c in catalogs) ...[
                    if (c != catalogs.first) const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(c.name),
                      selected: !showFavourites && c == selected,
                      showCheckmark: false,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (_) {
                        if (showFavourites || c != selected) _pick(() => _selected = _key(c));
                      },
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 8),
              // The catalog stays mounted under search results so clearing returns to its scroll position.
              Expanded(
                child: IndexedStack(index: searching ? 1 : 0, children: [
                  HeroMode(
                    enabled: heroes && !searching,
                    child: showFavourites
                        // Keyed by the list so unfavouriting on Title shows here on return.
                        ? CatalogFeed.saved(favourites, key: ValueKey(favourites.map((f) => f.id).join(',')))
                        : selected == null
                            ? const CatalogNotice(Icons.video_library_outlined, 'No catalogs for this type yet.')
                            : CatalogFeed(selected, key: ValueKey(_key(selected))),
                  ),
                  HeroMode(
                    enabled: heroes && searching,
                    child: !searching
                        ? const SizedBox.shrink()
                        : searchable == null
                            ? CatalogNotice(Icons.search, "Your sources can't search these titles.",
                                action: 'Clear search', onAction: _clear)
                            : CatalogFeed(searchable,
                                query: _query, onClear: _clear, key: ValueKey((_key(searchable), _query))),
                  ),
                ]),
              ),
            ]),
          );
        },
      );
}

/// Movies / Series: selected is surface2 with the active-marker underline.
class _Segment extends StatelessWidget {
  const _Segment(this.label, {required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected ? FlickTokens.surface2 : FlickTokens.background,
          borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: selected ? null : onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: FlickTokens.minTouchTarget),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      width: 3, color: selected ? FlickTokens.activeMarker : FlickTokens.background),
                ),
              ),
              child: Text(label, style: FlickText.button),
            ),
          ),
        ),
      );
}

/// Selection stays distinct from focus: the slash marks selection; the frame
/// supplies the only focus owner, activation action and ring.
class _TvChoice extends StatelessWidget {
  const _TvChoice(this.label, {
    required this.selected,
    required this.onActivate,
    this.icon,
    this.focusNode,
  });

  final String label;
  final bool selected;
  final VoidCallback onActivate;
  final IconData? icon;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: FocusFrame.button(
          focusNode: focusNode,
          onActivate: onActivate,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (selected) ...[
                  const SlashMarker(),
                  const SizedBox(width: 8),
                ],
                if (icon != null) ...[
                  Icon(icon, size: 20, color: FlickTokens.textSecondary),
                  const SizedBox(width: 8),
                ],
                Text(label, style: FlickTv.body.copyWith(
                  color: selected ? FlickTokens.textPrimary : FlickTokens.textSecondary,
                )),
              ]),
            ),
          ),
        ),
      );
}

/// One viewport for header, filters, results and feedback. The shell already
/// places the content's left edge at x 144; only the right inset is added here.
class _TvDiscoverScroll extends StatelessWidget {
  const _TvDiscoverScroll({
    this.header,
    this.controller,
    required this.slivers,
  });

  final Widget? header;
  final ScrollController? controller;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: FlickTv.insetH),
        child: CustomScrollView(
          controller: controller,
          cacheExtent: MediaQuery.sizeOf(context).height,
          slivers: [
            if (header != null) SliverToBoxAdapter(child: header),
            ...slivers,
            const SliverToBoxAdapter(child: SizedBox(height: FlickTv.insetV)),
          ],
        ),
      );
}

/// One catalog (or one search) paged in as the viewer nears the end.
class CatalogFeed extends StatefulWidget {
  const CatalogFeed(Catalog this.catalog, {
    this.query,
    this.onClear,
    this.tvHeader,
    this.onAddSources,
    super.key,
  }) : saved = null;

  /// The device favourites: one fixed page, no paging.
  const CatalogFeed.saved(List<MetaPreview> this.saved, {
    this.tvHeader,
    this.onAddSources,
    super.key,
  })  : catalog = null,
        query = null,
        onClear = null;
  final Catalog? catalog;
  final List<MetaPreview>? saved;
  final String? query;
  final VoidCallback? onClear;
  final Widget? tvHeader;
  final VoidCallback? onAddSources;

  @override
  State<CatalogFeed> createState() => _CatalogFeedState();
}

class _CatalogFeedState extends State<CatalogFeed> {
  final _items = <MetaPreview>[];
  final _ids = <String>{};
  bool _loading = false, _done = false;
  Object? _error;

  // TV: one focus node per title, so a move can focus an index that was not built yet.
  final _scroll = ScrollController();
  final _focus = <String, FocusNode>{};
  double _row = 0;

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Up/Down in the lazy grid: the default policy first; when it finds no built poster, jump the target row
  /// (one row of [FlickTv.columns]) into view and focus that index in the next frame.
  Object? _move(DirectionalFocusIntent intent) {
    final from = primaryFocus;
    if (from == null || from.focusInDirection(intent.direction)) return null;
    final down = intent.direction == TraversalDirection.down;
    if (!down && intent.direction != TraversalDirection.up) return null;
    final index = _items.indexWhere((m) => _focus[m.id] == from);
    if (index < 0 || !_scroll.hasClients) return null;
    final target = (index + (down ? FlickTv.columns : -FlickTv.columns)).clamp(0, _items.length - 1);
    final rows = target ~/ FlickTv.columns - index ~/ FlickTv.columns;
    if (rows == 0) return null;
    final p = _scroll.position;
    p.jumpTo((p.pixels + rows * (_row + FlickTv.gridGap)).clamp(p.minScrollExtent, p.maxScrollExtent));
    final id = _items[target].id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final node = _focus[id];
      if (mounted && node?.context != null) tvReveal(node!);
    });
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.saved case final saved?) {
      _items.addAll(saved);
      _done = true;
    }
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    final catalog = widget.catalog!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await addons.catalog(catalog, search: widget.query, skip: _items.length);
      // Pages can overlap; a page with nothing new ends the feed, and Hero tags stay unique.
      final fresh = page.where((m) => _ids.add(m.id)).toList();
      _items.addAll(fresh);
      _done = fresh.isEmpty;
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  // Keep builders indexable so directional traversal can later materialize an
  // unbuilt target index without changing the artwork or caption widgets.
  Widget _buildTvItem(BuildContext context, int index) => _TvPoster(
        _items[index],
        focusNode: _focus.putIfAbsent(_items[index].id, () => FocusNode(debugLabel: 'poster $index')),
        key: ValueKey(_items[index].id),
      );

  Widget _buildTvSkeleton(BuildContext context, int index) => const _TvPosterSkeleton();

  Widget _buildTv(BuildContext context, BoxConstraints box) {
    final width = (box.maxWidth - FlickTv.insetH - FlickTv.gridPad * 2 -
        FlickTv.gridGap * (FlickTv.columns - 1)) / FlickTv.columns;
    final scaler = MediaQuery.textScalerOf(context);
    final caption = scaler.scale(FlickTv.card.fontSize!) * FlickTv.card.height! +
        scaler.scale(FlickTv.meta.fontSize!) * FlickTv.meta.height!;
    final grid = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: FlickTv.columns,
      crossAxisSpacing: FlickTv.gridGap,
      mainAxisSpacing: FlickTv.gridGap,
      mainAxisExtent: _row = width / FlickTv.posterAspect + 8 + caption,
    );
    final slivers = <Widget>[];

    if (_items.isEmpty && _error != null) {
      slivers.add(SliverToBoxAdapter(
        child: _TvNotice(
          _offline(_error) ? Icons.wifi_off : Icons.report_outlined,
          _offline(_error) ? "You're offline. Check your connection and try again." : "Couldn't load these titles.",
          action: 'Retry',
          onAction: _more,
        ),
      ));
    } else if (_items.isEmpty && _done) {
      slivers.add(SliverToBoxAdapter(
        child: _TvNotice(
          widget.query == null ? Icons.video_library_outlined : Icons.search,
          widget.query == null ? 'No titles in this catalog yet.' : 'Nothing found for “${widget.query}”',
          action: widget.query == null ? 'Add sources' : 'Clear search',
          onAction: widget.query == null ? widget.onAddSources : widget.onClear,
        ),
      ));
    } else {
      slivers.add(SliverPadding(
        padding: const EdgeInsets.all(FlickTv.gridPad),
        sliver: SliverGrid.builder(
          gridDelegate: grid,
          itemCount: _items.isEmpty ? FlickTv.columns * 2 : _items.length,
          itemBuilder: _items.isEmpty ? _buildTvSkeleton : _buildTvItem,
        ),
      ));
      if (_items.isNotEmpty && _loading) {
        slivers.add(SliverPadding(
          padding: const EdgeInsets.all(FlickTv.gridPad),
          sliver: SliverGrid.builder(
            gridDelegate: grid,
            itemCount: FlickTv.columns,
            itemBuilder: _buildTvSkeleton,
          ),
        ));
      }
      if (_items.isNotEmpty && _error != null) {
        slivers.add(SliverToBoxAdapter(
          child: _TvNotice(
            _offline(_error) ? Icons.wifi_off : Icons.report_outlined,
            _offline(_error) ? "You're offline. Check your connection." : "Couldn't load more titles.",
            action: 'Retry',
            onAction: _more,
          ),
        ));
      }
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0 && n.metrics.axis == Axis.vertical &&
            _error == null && n.metrics.extentAfter < MediaQuery.sizeOf(context).height) {
          _more();
        }
        return false;
      },
      child: Actions(
        actions: {DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(onInvoke: _move)},
        child: _TvDiscoverScroll(header: widget.tvHeader, controller: _scroll, slivers: slivers),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        if (context.tv) return _buildTv(context, box);
        // Three columns: 98.7×148 art + two caption lines = 188dp cells at 360dp and 1× text.
        final caption = MediaQuery.textScalerOf(context).scale(16) * 2;
        final width = (box.maxWidth - FlickTokens.pageGutter * 2 - FlickTokens.railGap * 2) / 3;
        final grid = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: FlickTokens.railGap,
          mainAxisSpacing: FlickTokens.railGap,
          mainAxisExtent: width * 3 / 2 + 8 + caption,
        );
        const gutters = EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter);

        if (_items.isEmpty) {
          if (_error != null) {
            return _offline(_error)
                ? CatalogNotice(Icons.wifi_off, "Couldn't connect. Check your connection and try again.", action: 'Try again', onAction: _more)
                : CatalogNotice(Icons.report_outlined, "Couldn't load these titles", action: 'Try again', onAction: _more);
          }
          if (!_done) return GridSkeleton(padding: gutters, delegate: grid);
          return widget.query == null
              ? const CatalogNotice(Icons.video_library_outlined, 'No titles in this catalog yet.')
              : CatalogNotice(Icons.search, 'Nothing found for “${widget.query}”',
                  action: 'Clear search', onAction: widget.onClear);
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (_error == null && n.metrics.extentAfter < 600) _more();
            return false;
          },
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: gutters,
              sliver: SliverGrid.builder(
                gridDelegate: grid,
                itemCount: _items.length,
                itemBuilder: (_, i) => _Poster(_items[i], caption: caption),
              ),
            ),
            if (_loading)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: FlickTokens.railGap + grid.mainAxisExtent!,
                  child: GridSkeleton(padding: gutters.copyWith(top: FlickTokens.railGap), delegate: grid),
                ),
              ),
            if (_error != null)
              SliverToBoxAdapter(
                child: Semantics(
                  liveRegion: true,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 12, FlickTokens.pageGutter, 0),
                    child: Row(children: [
                      Icon(_offline(_error) ? Icons.wifi_off : Icons.report_outlined,
                          color: FlickTokens.textSecondary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_offline(_error) ? "Couldn't connect. Check your connection." : "Couldn't load more titles",
                            style: FlickText.body),
                      ),
                      const SizedBox(width: 8),
                      TextButton(onPressed: _more, child: const Text('Retry')),
                    ]),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        );
      });
}

/// Phone and TV share the existing Hero tag, preview and fade route.
void _openTitle(BuildContext context, MetaPreview m) {
  final d = MediaQuery.disableAnimationsOf(context) ? Duration.zero : FlickTokens.sheetDuration;
  final preview = (
    id: m.id,
    type: m.type == 'anime' ? 'series' : m.type,
    name: m.name,
    poster: m.poster,
    releaseInfo: m.releaseInfo,
  );
  Navigator.push(
    context,
    PageRouteBuilder<void>(
      transitionDuration: d,
      reverseTransitionDuration: d,
      pageBuilder: (_, _, _) => TitleScreen(preview),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a.drive(CurveTween(curve: FlickTokens.curveIn)), child: child),
    ),
  );
}

class _TvPoster extends StatelessWidget {
  const _TvPoster(this.preview, {required this.focusNode, super.key});
  final MetaPreview preview;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final m = preview;
    final year = RegExp(r'\d{4}').firstMatch(m.releaseInfo ?? '')?.group(0);
    void open() => _openTitle(context, m);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FocusFrame(
        focusNode: focusNode,
        lift: true,
        semanticLabel: year == null ? m.name : '${m.name}, $year',
        onActivate: open,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            canRequestFocus: false,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
            onTap: open,
            child: AspectRatio(
              aspectRatio: FlickTv.posterAspect,
              child: Hero(
                tag: m.id,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
                  child: NetImage(m.poster ?? ''),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      ExcludeSemantics(
        child: Text(m.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlickTv.card.copyWith(color: FlickTokens.textPrimary)),
      ),
      ExcludeSemantics(
        child: Text(year ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlickTv.meta.copyWith(color: FlickTokens.textSecondary)),
      ),
    ]);
  }
}

/// The same art, title and year geometry as a real TV cell; loading never
/// requests focus or transfers it away from the switch.
class _TvPosterSkeleton extends StatelessWidget {
  const _TvPosterSkeleton();

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final titleHeight = scaler.scale(FlickTv.card.fontSize!) * FlickTv.card.height!;
    final yearHeight = scaler.scale(FlickTv.meta.fontSize!) * FlickTv.meta.height!;
    return ExcludeSemantics(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AspectRatio(
          aspectRatio: FlickTv.posterAspect,
          child: Skeleton(radius: FlickTokens.artworkRadius),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: titleHeight,
          child: const Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.8,
              child: Skeleton(height: 14, radius: FlickTokens.grid),
            ),
          ),
        ),
        SizedBox(
          height: yearHeight,
          child: const Align(
            alignment: Alignment.centerLeft,
            child: Skeleton(width: 40, height: 10, radius: FlickTokens.grid),
          ),
        ),
      ]),
    );
  }
}

class _Poster extends StatefulWidget {
  const _Poster(this.preview, {required this.caption});
  final MetaPreview preview;
  final double caption;

  @override
  State<_Poster> createState() => _PosterState();
}

class _PosterState extends State<_Poster> {
  bool _pressed = false;

  void _press(bool down) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  void _open() => _openTitle(context, widget.preview);

  @override
  Widget build(BuildContext context) {
    final m = widget.preview;
    final still = MediaQuery.disableAnimationsOf(context);
    final year = RegExp(r'\d{4}').firstMatch(m.releaseInfo ?? '')?.group(0);
    return Semantics(
      button: true,
      label: year == null ? m.name : '${m.name}, $year',
      onTap: _open,
      excludeSemantics: true,
      child: Listener(
        onPointerDown: (_) => _press(true),
        onPointerUp: (_) => _press(false),
        onPointerCancel: (_) => _press(false),
        child: AnimatedScale(
          scale: !still && _pressed ? 0.97 : 1,
          duration: still ? Duration.zero : FlickTokens.stateDuration,
          curve: FlickTokens.curveIn,
          child: InkWell(
            borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
            onTap: _open,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: Hero(
                  tag: m.id,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
                    child: NetImage(m.poster ?? ''),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: widget.caption,
                child: Text(m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: FlickText.metadata.copyWith(color: FlickTokens.textPrimary)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// TV feedback is a sliver child, so it scrolls with the header and grid.
class _TvNotice extends StatelessWidget {
  const _TvNotice(this.icon, this.text, {this.action, this.onAction});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(FlickTv.gridPad, 16, FlickTv.gridPad, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 32, color: FlickTokens.textSecondary),
            const SizedBox(height: 12),
            Text(text, style: FlickTv.body),
            if (action != null && onAction != null) ...[
              const SizedBox(height: 12),
              // Becomes the target only when focus was lost: autofocus never takes it from a focused item.
              FocusFrame.button(
                autofocus: true,
                onActivate: onAction,
                child: Container(
                  constraints: const BoxConstraints(minHeight: FlickTokens.minTouchTarget),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                  decoration: BoxDecoration(
                    border: Border.all(color: FlickTokens.outline),
                    borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
                  ),
                  child: Text(action!, style: FlickTv.body),
                ),
              ),
            ],
          ]),
        ),
      );
}

/// A state that starts in the grid area: icon, sentence, optional action.
class CatalogNotice extends StatelessWidget {
  const CatalogNotice(this.icon, this.text, {this.action, this.onAction, super.key});
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 16, FlickTokens.pageGutter, 24),
        child: Semantics(
          liveRegion: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 32, color: FlickTokens.textSecondary),
            const SizedBox(height: 12),
            Text(text, style: FlickText.body),
            if (action != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(action!)),
            ],
          ]),
        ),
      );
}
