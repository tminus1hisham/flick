import 'package:flutter/material.dart';

import '../jellyfin.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

const _gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 130,
  childAspectRatio: 0.46,
  crossAxisSpacing: FlickTokens.railGap,
  mainAxisSpacing: 20,
);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Future<List<Item>>? _results;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(String q) => setState(() {
        _query = q;
        _results = session.client!.items(searchTerm: q);
      });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 12, FlickTokens.pageGutter, 16),
        child: SizedBox(
          height: 52,
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search',
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close),
                      onPressed: _controller.clear,
                    ),
            ),
            onSubmitted: (q) {
              if (q.trim().isEmpty) return;
              _run(q.trim());
            },
          ),
        ),
      ),
      Expanded(
        child: _results == null
            ? const _Message(icon: Icons.search, title: 'Find something to watch', body: 'Search your connected libraries.')
            : Loader(
                _results!,
                onRetry: () => _run(_query),
                placeholder: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
                  gridDelegate: _gridDelegate,
                  itemCount: 12,
                  itemBuilder: (_, _) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    AspectRatio(aspectRatio: 2 / 3, child: Skeleton(radius: FlickTokens.artworkRadius)),
                    SizedBox(height: 8),
                    Skeleton(width: 80, height: 12, radius: 4),
                  ]),
                ),
                (items) => items.isEmpty
                    ? _Message(
                        title: 'No matches for “$_query”',
                        body: 'Check the spelling or try another title.',
                      )
                    : CustomScrollView(slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 0, FlickTokens.pageGutter, 12),
                          sliver: SliverToBoxAdapter(
                            child: Text(
                              items.length == 1 ? '1 result' : '${items.length} results',
                              style: text.labelMedium?.copyWith(color: secondary),
                            ),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 0, FlickTokens.pageGutter, 24),
                          sliver: SliverGrid.builder(
                            gridDelegate: _gridDelegate,
                            itemCount: items.length,
                            itemBuilder: (_, i) => Poster(items[i], width: double.infinity),
                          ),
                        ),
                      ]),
              ),
      ),
    ]);
  }
}

class _Message extends StatelessWidget {
  const _Message({this.icon, required this.title, required this.body});
  final IconData? icon;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 40, color: scheme.onSurfaceVariant), const SizedBox(height: 16)],
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(body, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
