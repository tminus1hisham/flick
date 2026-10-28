import 'package:flutter/material.dart';

import '../jellyfin.dart';
import '../state.dart';
import '../widgets.dart';

class LibrariesScreen extends StatefulWidget {
  const LibrariesScreen({super.key});

  @override
  State<LibrariesScreen> createState() => _LibrariesScreenState();
}

class _LibrariesScreenState extends State<LibrariesScreen> {
  late Future<List<Item>> _views = session.client!.views();

  @override
  Widget build(BuildContext context) => Loader(
        _views,
        onRetry: () => setState(() => _views = session.client!.views()),
        (views) => ListView(children: [
          for (final v in views)
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(v.name),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => LibraryGrid(view: v))),
            ),
        ]),
      );
}

class LibraryGrid extends StatefulWidget {
  const LibraryGrid({required this.view, super.key});
  final Item view;

  @override
  State<LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends State<LibraryGrid> {
  final _items = <Item>[];
  bool _loading = false, _done = false;
  Object? _error;

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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.view.name)),
        body: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) _more();
            return false;
          },
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140, childAspectRatio: 0.5, crossAxisSpacing: 12),
                itemCount: _items.length,
                itemBuilder: (_, i) => Poster(_items[i], width: double.infinity),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: _error != null
                    ? TextButton(onPressed: _more, child: Text('$_error · Retry'))
                    : _loading
                        ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
                        : const SizedBox.shrink(),
              ),
            ),
          ]),
        ),
      );
}
