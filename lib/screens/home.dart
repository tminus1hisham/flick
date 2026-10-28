import 'package:flutter/material.dart';

import '../jellyfin.dart';
import '../state.dart';
import '../widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<(String, List<Item>)>> _rows = _load();

  Future<List<(String, List<Item>)>> _load() async {
    final c = session.client!;
    final views = await c.views();
    final latest = await Future.wait(views.map((v) => c.latest(v.id)));
    return [
      ('Continue watching', await c.resume()),
      for (var i = 0; i < views.length; i++) ('Latest in ${views[i].name}', latest[i]),
    ];
  }

  void _reload() => setState(() => _rows = _load());

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async {
          _reload();
          await _rows;
        },
        child: Loader(
          _rows,
          onRetry: _reload,
          (rows) => ListView(children: [for (final (t, items) in rows) PosterRow(t, items)]),
        ),
      );
}
