import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../addons.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'title.dart';
import 'torrent.dart' show MagnetButton;

(String, String, String) _key(Catalog c) => (c.addon.base, c.type, c.id);
const _favourites = ('', '', 'favourites');

// The client can't tell offline from an addon being down: both are AddonError.unreachable.
bool _offline(Object? e) => e is AddonException && e.kind == AddonError.unreachable;

/// D1: addon catalogs as a poster wall, with search over the current type.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _search = TextEditingController();
  String _type = 'movie', _query = '';
  (String, String, String)? _selected;

  @override
  void dispose() {
    _search.dispose();
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
                  const SizedBox(width: 12),
                  const MagnetButton(),
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
                        ? _Feed.saved(favourites, key: ValueKey(favourites.map((f) => f.id).join(',')))
                        : selected == null
                            ? const _Notice(Icons.video_library_outlined, 'No catalogs for this type yet.')
                            : _Feed(selected, key: ValueKey(_key(selected))),
                  ),
                  HeroMode(
                    enabled: heroes && searching,
                    child: !searching
                        ? const SizedBox.shrink()
                        : searchable == null
                            ? _Notice(Icons.search, "Your sources can't search these titles.",
                                action: 'Clear search', onAction: _clear)
                            : _Feed(searchable,
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

/// One catalog (or one search) paged in as the viewer nears the end.
class _Feed extends StatefulWidget {
  const _Feed(Catalog this.catalog, {this.query, this.onClear, super.key}) : saved = null;

  /// The device favourites: one fixed page, no paging.
  const _Feed.saved(List<MetaPreview> this.saved, {super.key})
      : catalog = null,
        query = null,
        onClear = null;
  final Catalog? catalog;
  final List<MetaPreview>? saved;
  final String? query;
  final VoidCallback? onClear;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  final _items = <MetaPreview>[];
  final _ids = <String>{};
  bool _loading = false, _done = false;
  Object? _error;

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

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
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
                ? _Notice(Icons.wifi_off, "Couldn't connect. Check your connection and try again.", action: 'Try again', onAction: _more)
                : _Notice(Icons.report_outlined, "Couldn't load these titles", action: 'Try again', onAction: _more);
          }
          if (!_done) return GridSkeleton(padding: gutters, delegate: grid);
          return widget.query == null
              ? const _Notice(Icons.video_library_outlined, 'No titles in this catalog yet.')
              : _Notice(Icons.search, 'Nothing found for “${widget.query}”',
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

  void _open() {
    final d = MediaQuery.disableAnimationsOf(context) ? Duration.zero : FlickTokens.sheetDuration;
    Navigator.push(
      context,
      PageRouteBuilder<void>(
        transitionDuration: d,
        reverseTransitionDuration: d,
        pageBuilder: (_, _, _) => TitleScreen(widget.preview),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a.drive(CurveTween(curve: FlickTokens.curveIn)), child: child),
      ),
    );
  }

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

/// A state that starts in the grid area: icon, sentence, optional action.
class _Notice extends StatelessWidget {
  const _Notice(this.icon, this.text, {this.action, this.onAction});
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
