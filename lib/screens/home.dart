import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../addons.dart';
import '../kit/focus.dart';
import '../kit/sidebar.dart';
import '../state.dart';
import '../theme.dart';
import '../trailers.dart';
import '../widgets.dart';
import 'continue_watching.dart';
import 'discover.dart' show BrowseScreen;
import 'history.dart';
import 'movie_queue.dart';
import 'title.dart';

typedef PreviewBuilder = Widget Function(Trailer trailer, ValueChanged<String> onEvent);
final homeRouteObserver = RouteObserver<ModalRoute<void>>();

/// The browser stays a separate route, so returning restores every home row.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({this.active = true, this.onAddSources, this.previewBuilder, super.key});
  final bool active;
  final VoidCallback? onAddSources;
  final PreviewBuilder? previewBuilder;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> with WidgetsBindingObserver, RouteAware {
  final _pages = <(String, String, String), Future<List<MetaPreview>>>{};
  final _scroll = ScrollController();
  final _previewBounds = GlobalKey();
  final _viewportBounds = GlobalKey();
  bool _foreground = true, _covered = false, _visible = true;
  bool _visibilityQueued = false;
  String? _notice;
  int _revision = 0;
  ModalRoute<void>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (_route != route) {
      homeRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) homeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() { if (mounted) setState(() => _covered = true); }
  @override
  void didPopNext() { if (mounted) setState(() => _covered = false); }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_visibility);
    addons.addListener(_sourcesChanged);
  }

  void _sourcesChanged() {
    _pages.clear();
    _revision++;
    if (mounted) setState(() {});
  }

  void _visibility() {
    if (_visibilityQueued) return;
    _visibilityQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityQueued = false;
      if (mounted) _measureVisibility();
    });
  }

  void _measureVisibility() {
    final box = _previewBounds.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final y = box.localToGlobal(Offset.zero).dy;
    final viewport = _viewportBounds.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final visible = y + box.size.height > top && y < top + viewport.size.height;
    if (visible != _visible) setState(() => _visible = visible);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _foreground = state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    homeRouteObserver.unsubscribe(this);
    addons.removeListener(_sourcesChanged);
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    super.dispose();
  }

  Future<List<MetaPreview>> _page(Catalog catalog) => _pages.putIfAbsent(
    (catalog.addon.scopeId, catalog.type, catalog.id), () => addons.catalog(catalog).then((items) {
      final seen = <Object>{};
      return items.where((p) => seen.add(previewKey(p))).toList();
    }));

  Future<void> _open(Widget page) async {
    setState(() => _covered = true);
    try {
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
    } finally {
      if (mounted) setState(() => _covered = false);
    }
  }

  Future<void> _previews() async {
    try {
      await settings.saveAutoplayPreviews(!settings.autoplayPreviews);
      if (mounted) setState(() => _notice = null);
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not save preview preference. Try again.');
    }
  }

  void _browse([Catalog? catalog]) => _open(_BrowsePage(catalog: catalog,
    onAddSources: widget.onAddSources == null ? null : () {
      Navigator.of(context).pop();
      widget.onAddSources!();
    }));

  Future<void> _queue() async {
    if (context.tv) { return _open(const MovieQueueScreen()); }
    setState(() => _covered = true);
    try {
      await showPlaybackSidebar<void>(context, (_) => const MovieQueueScreen());
    } finally {
      if (mounted) setState(() => _covered = false);
    }
  }

  Widget _header(BuildContext context) {
    final compact = !context.tv;
    final actions = [
      InitialFocus(child: HomeAction('Browse / Search', Icons.search, () => _browse(), compact: compact)),
      HomeAction('Viewing history', Icons.history, () => _open(HistoryScreen(history)), compact: compact),
      HomeAction('Playback queue', Icons.playlist_play, _queue, compact: compact),
      HomeAction('Autoplay previews: ${settings.autoplayPreviews ? 'On' : 'Off'}',
        settings.autoplayPreviews ? Icons.videocam_outlined : Icons.videocam_off_outlined, _previews, compact: compact),
    ];
    final title = Text('Discover', style: context.tv ? FlickTv.page : FlickText.pageTitle);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (context.tv) ...[
        title, const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: actions),
      ] else Row(children: [Expanded(child: title), ...actions]),
      if (_notice != null) Text(_notice!, style: FlickText.body),
      const SizedBox(height: FlickTokens.sectionGap),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final catalogs = addons.catalogs.where((c) => c.type == 'movie' || c.type == 'series').toList();
    Catalog? popular(String type) => catalogs.where((c) => c.addon.bundled && c.id == 'top' && c.type == type).firstOrNull;
    final movies = popular('movie'), series = popular('series');
    final rows = [?movies, ?series,
      ...catalogs.where((c) => c != movies && c != series)];
    return SafeArea(bottom: false, child: FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
      child: ListenableBuilder(listenable: saved, builder: (context, _) => ListView.builder(
        key: _viewportBounds,
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(context.tv ? FlickTv.gridPad : FlickTokens.pageGutter,
          context.tv ? FlickTv.insetV : 8, context.tv ? FlickTv.insetH : FlickTokens.pageGutter, FlickTokens.sectionGap),
        itemCount: 5 + rows.length,
        itemBuilder: (context, index) {
          if (index == 0) { return _header(context); }
          if (index == 1) { return movies == null
            ? Text('Add a movie catalog to discover featured titles.', style: FlickText.body)
            : FeaturedMovies(key: ValueKey(_page(movies)), candidates: _page(movies),
                active: widget.active && _foreground && !_covered && _visible,
                autoplay: settings.autoplayPreviews, previewBuilder: widget.previewBuilder, previewKey: _previewBounds,
                onOpen: (p) => _open(TitleScreen(p)), onRetry: _sourcesChanged); }
          if (index == 2) return const ContinueWatching();
          if (index == 3 || index == 4) {
            final items = index == 3 ? saved.myList : saved.favourites;
            if (items.isEmpty) return const SizedBox.shrink();
            return HomeRow(key: ValueKey(index), label: index == 3 ? 'My List' : 'Favourites',
              items: items, onOpen: (p) => _open(TitleScreen(p)));
          }
          final c = rows[index - 5];
          return _CatalogRow(key: ValueKey((_revision, c.addon.scopeId, c.type, c.id)),
            label: c == movies ? 'Popular Movies' : c == series ? 'Popular Series' : '${c.name} · ${c.addon.name}',
            numbered: c == movies, load: () => _page(c),
            retry: () { _pages.remove((c.addon.scopeId, c.type, c.id)); },
            onOpen: (p) => _open(TitleScreen(p)),
            onAll: () => _browse(c));
        },
      )),
    ));
  }
}

class _BrowsePage extends StatefulWidget {
  const _BrowsePage({this.onAddSources, this.catalog});
  final VoidCallback? onAddSources;
  final Catalog? catalog;
  @override
  State<_BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<_BrowsePage> {
  final _scope = FocusScopeNode(debugLabel: 'Browse');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && context.tv) enterScope(_scope); });
  }
  @override
  void dispose() { _scope.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !context.tv,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      final focus = primaryFocus?.context;
      if (focus == null || Actions.maybeInvoke(focus, const DismissIntent()) != true) Navigator.pop(context);
    },
    child: Scaffold(appBar: context.tv ? null : AppBar(title: const Text('Browse')),
      body: FocusScope(node: _scope, child: BrowseScreen(onAddSources: widget.onAddSources, initialCatalog: widget.catalog))),
  );
}

class HomeAction extends StatelessWidget {
  const HomeAction(this.label, this.icon, this.onTap, {this.compact = false, super.key});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = compact ? SizedBox.square(dimension: FlickTokens.minTouchTarget, child: Icon(icon, size: 24))
      : Padding(padding: const EdgeInsets.all(12), child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 24), const SizedBox(width: 8),
      Flexible(child: Text(label, style: context.tv ? FlickTv.meta : FlickText.button)),
    ]));
    return Tooltip(message: label, excludeFromSemantics: true, child: context.tv ? RevealArea(child: FocusFrame.button(semanticLabel: label, onActivate: onTap,
      child: DecoratedBox(decoration: BoxDecoration(color: FlickTokens.surface2,
        borderRadius: BorderRadius.circular(FlickTokens.controlRadius)), child: content)))
      : Semantics(button: true, label: compact ? label : null, onTap: compact ? onTap : null,
          excludeSemantics: compact, child: Material(color: compact ? FlickTokens.background : FlickTokens.surface2,
          borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
          child: InkWell(borderRadius: BorderRadius.circular(FlickTokens.controlRadius), onTap: onTap, child: content))));
  }
}

class _CatalogRow extends StatefulWidget {
  const _CatalogRow({required this.label, required this.numbered, required this.load, required this.retry,
    required this.onOpen, required this.onAll, super.key});
  final String label;
  final bool numbered;
  final Future<List<MetaPreview>> Function() load;
  final VoidCallback retry, onAll;
  final ValueChanged<MetaPreview> onOpen;
  @override
  State<_CatalogRow> createState() => _CatalogRowState();
}

class _CatalogRowState extends State<_CatalogRow> {
  late Future<List<MetaPreview>> _items = widget.load();
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MetaPreview>>(future: _items, builder: (context, snapshot) {
      if (snapshot.hasData) { return HomeRow(label: widget.label, items: snapshot.data!.take(widget.numbered ? 10 : 20).toList(),
        numbered: widget.numbered, onOpen: widget.onOpen, onAll: widget.onAll); }
      return Padding(padding: const EdgeInsets.symmetric(vertical: FlickTokens.railGap),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, style: context.tv ? FlickTv.railHeading : FlickText.railHeading),
          const SizedBox(height: 12),
          if (snapshot.hasError) ...[
            Text('Could not connect to this catalog. Check your connection or source.', style: FlickText.body),
            HomeAction('Retry ${widget.label}', Icons.refresh, () {
              widget.retry(); setState(() { _items = widget.load(); });
            }),
          ] else const Skeleton(height: 200),
        ]));
    });
  }
}

class HomeRow extends StatelessWidget {
  const HomeRow({required this.label, required this.items, required this.onOpen,
    this.onAll, this.numbered = false, super.key});
  final String label;
  final List<MetaPreview> items;
  final ValueChanged<MetaPreview> onOpen;
  final VoidCallback? onAll;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    final width = context.tv ? 168.0 : 112.0;
    final caption = MediaQuery.textScalerOf(context).scale(context.tv ? FlickTv.meta.fontSize! : FlickText.cardTitle.fontSize!) * 3;
    return Padding(padding: const EdgeInsets.symmetric(vertical: FlickTokens.railGap),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(label, style: context.tv ? FlickTv.railHeading : FlickText.railHeading),
          if (onAll != null) HomeAction('See all', Icons.arrow_forward, onAll!),
        ]),
        if (items.isEmpty) Text('No titles listed yet.', style: FlickText.body)
        else SizedBox(height: width * 1.5 + caption + 28, child: SingleChildScrollView(
          key: PageStorageKey(label), scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var i = 0; i < items.length; i++)
            Padding(padding: const EdgeInsets.only(right: 16), child: Builder(builder: (context) {
            final p = items[i];
            final content = SizedBox(width: width, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ClipRRect(borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
                child: SizedBox(width: width, height: width * 1.5,
                  child: p.poster == null ? const Skeleton() : NetImage(p.poster!))),
              const SizedBox(height: 8),
              Text('${numbered ? '${i + 1}. ' : ''}${p.name}', maxLines: 2, overflow: TextOverflow.ellipsis,
                style: context.tv ? FlickTv.meta : FlickText.cardTitle),
            ]));
            return context.tv ? RevealArea(child: FocusFrame.button(semanticLabel: p.name,
              onActivate: () => onOpen(p), child: content)) : Semantics(button: true,
                child: InkWell(onTap: () => onOpen(p), child: content));
          })),
          ]),
        )),
      ]));
  }
}

class FeaturedMovies extends StatefulWidget {
  const FeaturedMovies({required this.candidates, required this.active, required this.autoplay,
    required this.onOpen, required this.onRetry, this.previewBuilder, this.previewKey, super.key});
  final Future<List<MetaPreview>> candidates;
  final bool active, autoplay;
  final ValueChanged<MetaPreview> onOpen;
  final VoidCallback onRetry;
  final PreviewBuilder? previewBuilder;
  final GlobalKey? previewKey;
  @override
  State<FeaturedMovies> createState() => _FeaturedMoviesState();
}

class _FeaturedMoviesState extends State<FeaturedMovies> with AutomaticKeepAliveClientMixin {
  List<MetaPreview>? _picks;
  final _details = <Object, Meta>{};
  Timer? _timer;
  int _index = 0;
  bool _failed = false, _previewFailed = false, _playing = false, _paused = false, _reduce = false;
  bool _focused = false, _hovered = false, _pressed = false;
  String? _notice;
  bool get _running => widget.active && !_reduce && !_paused && !_focused && !_hovered && !_pressed;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final seen = <Object>{};
      final list = (await widget.candidates).where((p) => seen.add(previewKey(p))).toList()..shuffle(Random());
      if (!mounted) return;
      setState(() => _picks = list.take(5).toList());
      _schedule();
      for (final p in _picks!) {
        unawaited(_detail(p));
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _detail(MetaPreview p) async {
    try {
      final meta = await addons.scopedMeta(p.type, p.id, p.scope);
      if (mounted) {
        setState(() => _details[previewKey(p)] = meta);
      }
    } catch (_) { /* Artwork and title navigation remain available without metadata. */ }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running || (_picks?.length ?? 0) < 2 || _playing) return;
    _timer = Timer(const Duration(seconds: 10), () => _next(1));
  }

  void _next(int direction) {
    if ((_picks?.length ?? 0) < 2) return;
    setState(() {
      _index = (_index + direction) % _picks!.length;
      _previewFailed = false;
      _playing = false;
      _notice = null;
    });
    _schedule();
  }

  void _event(String event) {
    if (event == 'ended') {
      _playing = false;
      if (_running) _next(1);
    } else if (event == 'error' || event == 'blocked') {
      setState(() { _previewFailed = true; _playing = false; });
      _schedule();
    } else if (event == 'playing') {
      _playing = true;
      _timer?.cancel();
    } else if (event == 'paused') {
      _playing = false;
      setState(() => _paused = true);
      _timer?.cancel();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant FeaturedMovies oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active || !widget.autoplay) _playing = false;
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _save(MetaPreview p) async {
    try {
      await saved.toggleMyList(p);
      if (mounted) setState(() => _notice = null);
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not save My List. Try again.');
    }
  }

  Future<void> _external(Trailer trailer) async {
    try {
      await openExternal(trailerLink(trailer));
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not open trailer: ${trailerLink(trailer)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_failed) { return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Featured movies could not connect.', style: FlickText.body),
      HomeAction('Retry featured movies', Icons.refresh, widget.onRetry),
    ]); }
    if (_picks == null) return const Skeleton(height: 300);
    if (_picks!.isEmpty) { return Text('No featured movies listed yet.', style: FlickText.body); }
    final p = _picks![_index], meta = _details[previewKey(_picks![_index])];
    final trailer = meta?.trailers.firstOrNull;
    final preview = trailer != null && widget.active && widget.autoplay && !_reduce && !_previewFailed;
    final artwork = meta?.background ?? p.poster;
    return Focus(onFocusChange: (focused) { _focused = focused; _schedule(); },
      child: MouseRegion(onEnter: (_) { _hovered = true; _schedule(); },
        onExit: (_) { _hovered = false; _schedule(); },
        child: Listener(onPointerDown: (_) { _pressed = true; _schedule(); },
          onPointerUp: (_) { _pressed = false; _schedule(); },
          onPointerCancel: (_) { _pressed = false; _schedule(); },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TONIGHT’S PICK', style: FlickText.smallLabel.copyWith(color: FlickTokens.accent)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final height = max(200.0, min(context.tv ? 360.0 : 280.0, constraints.maxWidth * 9 / 16));
              return ClipRRect(borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
                child: SizedBox(key: widget.previewKey, height: height, width: double.infinity,
                  child: preview ? KeyedSubtree(key: ValueKey((previewKey(p), trailer)),
                    child: (widget.previewBuilder ?? ((t, event) => TrailerPreview(t,
                      onEvent: event)))(trailer, (event) {
                      if (mounted && widget.active && _picks![_index] == p) _event(event);
                    }))
                    : artwork == null ? const Skeleton() : NetImage(artwork, icon: false)));
            }),
            const SizedBox(height: 12),
            Text(p.name, style: context.tv ? FlickTv.title : FlickText.detailTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (meta?.description != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(meta!.description!, style: context.tv ? FlickTv.body : FlickText.body,
                maxLines: 2, overflow: TextOverflow.ellipsis)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              HomeAction('More Info', Icons.info_outline, () => widget.onOpen(p)),
              ListenableBuilder(listenable: saved, builder: (_, _) => HomeAction(
                saved.inMyList(p) ? 'Remove from My List' : 'My List',
                saved.inMyList(p) ? Icons.check : Icons.add, () => _save(p))),
              if (trailer != null) HomeAction('Watch Trailer', Icons.open_in_new, () => _external(trailer)),
            ]),
            if (_notice != null) Text(_notice!, style: FlickText.body),
            if (_picks!.length > 1) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                HomeAction('Previous', Icons.chevron_left, () => _next(-1)),
                Text('${_index + 1} / ${_picks!.length}', style: FlickText.metadata),
                HomeAction(_paused ? 'Resume rotation' : 'Pause rotation', _paused ? Icons.play_arrow : Icons.pause, () {
                  setState(() => _paused = !_paused); _schedule();
                }),
                HomeAction('Next', Icons.chevron_right, () => _next(1)),
              ])),
          ]),
        ),
      ),
    );
  }
}
