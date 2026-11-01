import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'kit/focus.dart';
import 'kit/rail.dart';
import 'screens/discover.dart';
import 'screens/anime.dart';
import 'screens/downloads.dart';
import 'screens/live.dart';
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
  await history.load();
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

/// Discover, Anime, Live and Downloads: bottom bar on phone, [FlickRail] plus Sources on TV.
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
      5, (i) => FocusScopeNode(debugLabel: 'tab $i', directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope));

  @override
  void initState() {
    super.initState();
    // Launch is the first entry into Discover.
    if (device.tv) WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  @override
  void dispose() {
    _rail.dispose();
    for (final t in _tabs) {
      t.dispose();
    }
    super.dispose();
  }

  /// Into the selected tab: its remembered item, else its [InitialFocus]; with neither, focus stays on the rail.
  void _enter() => enterScope(_tabs[_tab]);

  void _select(int i) {
    setState(() => _tab = i);
    // The tab becomes focusable once the IndexedStack shows it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _enter());
  }

  /// TV Back at the shell (system Back too): an open search or panel in the content closes first (it handles
  /// [DismissIntent], like Escape, and answers true); then content goes to the rail's selected item; the rail
  /// leaves the app.
  void _back() {
    final focus = primaryFocus?.context;
    if (_rail.hasFocus) {
      SystemNavigator.pop();
    } else if (focus == null || Actions.maybeInvoke(focus, const DismissIntent()) != true) {
      _rail.requestFocus();
    }
  }

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
                  DiscoverScreen(onAddSources: () => _select(4)),
                  AnimeTab(onAddSources: () => _select(4)),
                  LiveTab(active: _tab == 2),
                  Scaffold(appBar: _downloadsBar(), body: const DownloadsScreen()),
                  const SourcesScreen(),
                ].indexed)
                  // Only the visible tab's posters fly: a title in two tabs' grids would be two Heroes with one tag.
                  FocusScope(node: _tabs[i], child: HeroMode(enabled: i == _tab, child: tab)),
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
                  (icon: animeIcon, label: 'Anime'),
                  (icon: Icons.live_tv_outlined, label: 'Live'),
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
        appBar: _tab == 3 ? _downloadsBar() : null,
        body: IndexedStack(index: _tab, children: [const DiscoverScreen(), const AnimeTab(), LiveTab(active: _tab == 2), const DownloadsScreen()]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
            NavigationDestination(
                icon: AnimeGlyph(), selectedIcon: AnimeGlyph(filled: true), label: 'Anime'),
            NavigationDestination(
                icon: Icon(Icons.live_tv_outlined), selectedIcon: Icon(Icons.live_tv), label: 'Live'),
            NavigationDestination(
                icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          ],
        ),
      );
}

AppBar _downloadsBar() => AppBar(title: const Text('Downloads'), actions: const [MagnetButton()]);
