import 'package:flutter/material.dart';

import 'jellyfin.dart';
import 'screens/detail.dart';
import 'state.dart';

void openItem(BuildContext context, Item item) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => DetailScreen(item: item)));

class Poster extends StatelessWidget {
  const Poster(this.item, {this.width = 120, super.key});
  final Item item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = session.client!;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () => openItem(context, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  c.imageUrl(item.id),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: Colors.white10,
                    alignment: Alignment.center,
                    child: const Icon(Icons.movie_outlined),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(item.type == 'Episode' ? item.title : item.name,
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class PosterRow extends StatelessWidget {
  const PosterRow(this.title, this.items, {super.key});
  final String title;
  final List<Item> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => Poster(items[i]),
          ),
        ),
      ],
    );
  }
}

/// Renders [future]'s result, or a spinner / retryable error.
class Loader<T> extends StatelessWidget {
  const Loader(this.future, this.builder, {this.onRetry, super.key});
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${s.error}', textAlign: TextAlign.center),
                if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
              ]),
            );
          }
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return builder(s.data as T);
        },
      );
}
