import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/discover.dart';
import 'screens/anime.dart';
import 'screens/downloads.dart';
import 'screens/sources.dart';
import 'screens/torrent.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await settings.load();
  await downloads.init();
  await addons.load();
  await saved.load();
  runApp(const FlickApp());
}

class FlickApp extends StatelessWidget {
  const FlickApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flick',
        routes: {'/sources': (_) => const SourcesScreen()},
        debugShowCheckedModeBanner: false,
        theme: flickTheme(),
        builder: (_, child) => SplashHandoff(child: child!),
        home: const Shell(),
      );
}

/// Discover, Anime and Downloads.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        // Discover and Anime draw their own headers.
        appBar: _tab == 2 ? AppBar(title: const Text('Downloads'), actions: const [MagnetButton()]) : null,
        body: IndexedStack(index: _tab, children: const [DiscoverScreen(), AnimeTab(), DownloadsScreen()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
            NavigationDestination(
                icon: Icon(Icons.animation_outlined), selectedIcon: Icon(Icons.animation), label: 'Anime'),
            NavigationDestination(
                icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          ],
        ),
      );
}
