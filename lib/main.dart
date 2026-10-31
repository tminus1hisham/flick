import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'kit/focus.dart';
import 'kit/rail.dart';
import 'screens/discover.dart';
import 'screens/anime.dart';
import 'screens/downloads.dart';
import 'screens/sources.dart';
import 'screens/torrent.dart';
import 'state.dart';
import 'theme.dart';
import 'torrent.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await settings.load();
  await downloads.init();
  await addons.load();
  await saved.load();
  device.tv = await isTv();
  // The remote is a keyboard: the ring shows from the first frame, even before a key press.
  if (device.tv) FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  runApp(const FlickApp());
}

class FlickApp extends StatelessWidget {
  const FlickApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flick',
        routes: {'/sources': (_) => const SourcesScreen()},
        debugShowCheckedModeBanner: false,
        theme: flickTheme(tv: device.tv),
        shortcuts: device.tv ? tvShortcuts : null,
        builder: (_, child) => SplashHandoff(child: child!),
        home: const Shell(),
      );
}

/// Discover, Anime and Downloads: a bottom bar on the phone, the [FlickRail] (plus Sources) on TV.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  // TV only. One scope per tab remembers its last focused item; Left at a tab's edge searches the shell.
  final _rail = FocusScopeNode(debugLabel: 'rail');
  final _tabs = List.generate(
      4, (i) => FocusScopeNode(debugLabel: 'tab $i', directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope));

  @override
  void dispose() {
    _rail.dispose();
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  /// Into the selected tab: its remembered item, else its first focusable; with neither, focus stays on the rail.
  void _enter() {
    final scope = _tabs[_tab];
    (scope.focusedChild ?? scope.traversalDescendants.firstOrNull)?.requestFocus();
  }

  void _select(int i) {
    setState(() => _tab = i);
    // The tab becomes focusable once the IndexedStack shows it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  /// TV Back at the shell (system Back too): content goes to the rail's selected item; the rail leaves the app.
  void _back() => _rail.hasFocus ? SystemNavigator.pop() : _rail.requestFocus();

  @override
  Widget build(BuildContext context) => context.tv ? _tv() : _phone();

  Widget _tv() => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          body: Stack(children: [
            Padding(
              padding: const EdgeInsets.only(left: FlickTv.railColumn + FlickTv.contentGap),
              child: IndexedStack(index: _tab, children: [
                for (final (i, tab) in [
                  const DiscoverScreen(),
                  const AnimeTab(),
                  Scaffold(appBar: _downloadsBar(), body: const DownloadsScreen()),
                  const SourcesScreen(),
                ].indexed)
                  FocusScope(node: _tabs[i], child: tab),
              ]),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: FlickTv.railExpanded,
              child: FlickRail(
                scope: _rail,
                destinations: const [
                  (icon: Icons.explore_outlined, label: 'Discover'),
                  (icon: Icons.animation_outlined, label: 'Anime'),
                  (icon: Icons.download_outlined, label: 'Downloads'),
                ],
                bottom: (icon: Icons.settings_outlined, label: 'Sources'),
                selected: _tab,
                onSelect: _select,
                onRight: _enter,
              ),
            ),
          ]),
        ),
      );

  Widget _phone() => Scaffold(
        // Discover and Anime draw their own headers.
        appBar: _tab == 2 ? _downloadsBar() : null,
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

AppBar _downloadsBar() => AppBar(title: const Text('Downloads'), actions: const [MagnetButton()]);
