import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/discover.dart';
import 'screens/downloads.dart';
import 'screens/home.dart';
import 'screens/library.dart';
import 'screens/login.dart';
import 'screens/search.dart';
import 'screens/sources.dart';
import 'screens/torrent.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await session.load();
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
        home: ListenableBuilder(
          listenable: session,
          builder: (_, _) => session.loggedIn
              ? (session.online ? const Shell(key: ValueKey('member')) : const OfflineShell())
              : session.onboarded
                  // Keyed apart so the tab index resets when signing in or out.
                  ? const Shell(guest: true, key: ValueKey('guest'))
                  : const LoginScreen(),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({this.guest = false, super.key});

  /// No server: only Discover and Downloads.
  final bool guest;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  static const _home = (HomeScreen(), 'Home',
      NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'));
  static const _discover = (DiscoverScreen(), 'Discover',
      NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'));
  static const _browse = (BrowseScreen(), 'Browse',
      NavigationDestination(
          icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: 'Browse'));
  // Search has no outlined/filled pair in Material Icons.
  static const _search = (SearchScreen(), 'Search', NavigationDestination(icon: Icon(Icons.search), label: 'Search'));
  static const _downloads = (DownloadsScreen(), 'Downloads',
      NavigationDestination(
          icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'));

  @override
  Widget build(BuildContext context) {
    final tabs = widget.guest ? const [_discover, _downloads] : const [_home, _discover, _browse, _search, _downloads];
    final (_, name, _) = tabs[_tab];
    return Scaffold(
      // Home draws its own bar over the hero; Discover's search field is its header.
      appBar: name == 'Home' || name == 'Discover'
          ? null
          : AppBar(
              title: Text(name),
              actions: const [MagnetButton(), ProfileButton()],
            ),
      body: IndexedStack(index: _tab, children: [for (final (screen, _, _) in tabs) screen]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [for (final (_, _, destination) in tabs) destination],
      ),
    );
  }
}

class OfflineShell extends StatelessWidget {
  const OfflineShell({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads'), actions: const [MagnetButton()]),
      body: Column(children: [
        ColoredBox(
          color: FlickTokens.surface1,
          child: Padding(
            padding: const EdgeInsets.all(FlickTokens.pageGutter),
            child: Row(children: [
              Icon(Icons.wifi_off, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text("You're offline. Downloaded videos still play.",
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: session.recheck, child: const Text('Reconnect')),
            ]),
          ),
        ),
        const Expanded(child: DownloadsScreen()),
      ]),
    );
  }
}
