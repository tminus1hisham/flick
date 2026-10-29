import 'package:flutter/material.dart';

import '../jellyfin.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

const _gridPadding = EdgeInsets.fromLTRB(FlickTokens.pageGutter, 16, FlickTokens.pageGutter, 24);

/// Every library as a tab above its poster grid.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  late Future<List<Item>> _views = session.client!.views();

  @override
  Widget build(BuildContext context) => Loader(
        _views,
        onRetry: () => setState(() => _views = session.client!.views()),
        placeholder: const _BrowseSkeleton(),
        (views) => views.isEmpty
            ? Center(
                child: Text('No libraries on this server yet.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              )
            : DefaultTabController(
                length: views.length,
                child: Column(children: [
                  TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    // 4 + the tab's own 16 puts the first label on the 20dp gutter.
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    tabs: [for (final v in views) Tab(height: 48, text: v.name)],
                  ),
                  Expanded(
                    child: TabBarView(children: [for (final v in views) _Grid(v, key: ValueKey(v.id))]),
                  ),
                ]),
              ),
      );
}

/// One library's grid on its own page; Home's library chips open this.
class LibraryGrid extends StatelessWidget {
  const LibraryGrid({required this.view, super.key});
  final Item view;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(view.name)),
        body: _Grid(view),
      );
}

/// A library's posters, paged in as the viewer nears the end.
class _Grid extends StatefulWidget {
  const _Grid(this.view, {super.key});
  final Item view;

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> with AutomaticKeepAliveClientMixin {
  final _items = <Item>[];
  bool _loading = false, _done = false;
  Object? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await session.client!.items(parentId: widget.view.id, start: _items.length);
      _items.addAll(page);
      _done = page.isEmpty;
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_items.isEmpty) {
      if (_error != null) return ErrorState(_error!, onRetry: _more);
      if (_done) {
        return Center(
          child: Text('Nothing in this library yet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        );
      }
      return const GridSkeleton(padding: _gridPadding);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600) _more();
        return false;
      },
      child: CustomScrollView(slivers: [
        SliverPadding(
          padding: _gridPadding,
          sliver: SliverGrid.builder(
            gridDelegate: posterGrid,
            itemCount: _items.length,
            itemBuilder: (_, i) => Poster(_items[i], width: double.infinity),
          ),
        ),
        SliverToBoxAdapter(
          child: _error != null
              ? ErrorState(_error!, onRetry: _more)
              : _loading
                  ? const Padding(
                      padding: EdgeInsets.only(bottom: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : const SizedBox.shrink(),
        ),
      ]),
    );
  }
}

class _BrowseSkeleton extends StatelessWidget {
  const _BrowseSkeleton();

  @override
  Widget build(BuildContext context) => const Column(children: [
        SizedBox(
          height: 48,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
            child: Row(children: [
              Skeleton(width: 64, height: 14, radius: 4),
              SizedBox(width: 32),
              Skeleton(width: 56, height: 14, radius: 4),
              SizedBox(width: 32),
              Skeleton(width: 88, height: 14, radius: 4),
            ]),
          ),
        ),
        Expanded(child: GridSkeleton(padding: _gridPadding)),
      ]);
}
