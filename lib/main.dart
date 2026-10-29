import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'downloads.dart';
import 'screens/discover.dart';
import 'screens/downloads.dart';
import 'screens/player.dart';
import 'screens/sources.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await addons.load();
  await saved.load();
  await downloads.load();
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

/// Discover and Downloads. Discover's search field is its header and keeps clear of the status bar itself.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void _play(Download d) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => PlayerScreen(title: d.playback.title, source: d.path, playback: d.playback)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: _tab == 1 ? AppBar(title: const Text('Downloads')) : null,
        body: IndexedStack(index: _tab, children: [
          const DiscoverScreen(),
          // main() awaits downloads.load() before the app mounts, so there is no loading state here.
          DownloadsScreen(onPlay: _play),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          animationDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : FlickTokens.stateDuration,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: 'Discover'),
            NavigationDestination(
                icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download_rounded), label: 'Downloads'),
          ],
        ),
      );
}
