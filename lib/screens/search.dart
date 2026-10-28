import 'package:flutter/material.dart';

import '../jellyfin.dart';
import '../state.dart';
import '../widgets.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Future<List<Item>>? _results;

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
            onSubmitted: (q) {
              if (q.trim().isEmpty) return;
              setState(() => _results = session.client!.items(searchTerm: q.trim()));
            },
          ),
        ),
        Expanded(
          child: _results == null
              ? const SizedBox.shrink()
              : Loader(
                  _results!,
                  (items) => items.isEmpty
                      ? const Center(child: Text('No results'))
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 140, childAspectRatio: 0.5, crossAxisSpacing: 12),
                          itemCount: items.length,
                          itemBuilder: (_, i) => Poster(items[i], width: double.infinity),
                        ),
                ),
        ),
      ]);
}
