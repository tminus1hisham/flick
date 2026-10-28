import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/downloads.dart';
import 'screens/home.dart';
import 'screens/library.dart';
import 'screens/login.dart';
import 'screens/search.dart';
import 'screens/torrent.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await session.load();
  await downloads.init();
  runApp(const FlickApp());
}

class FlickApp extends StatelessWidget {
  const FlickApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Flick',
        theme: flickTheme(),
        home: ListenableBuilder(
          listenable: session,
          builder: (_, _) => !session.loggedIn
              ? const LoginScreen()
              : session.online
                  ? const Shell()
                  : const OfflineShell(),
        ),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  static const _tabs = [HomeScreen(), BrowseScreen(), SearchScreen(), DownloadsScreen()];
  static const _titles = ['', 'Browse', 'Search', 'Downloads'];

  @override
  Widget build(BuildContext context) => Scaffold(
        // Home draws its own bar over the hero.
        appBar: _tab == 0
            ? null
            : AppBar(
                title: Text(_titles[_tab]),
                actions: const [MagnetButton(), ProfileButton()],
              ),
        body: IndexedStack(index: _tab, children: _tabs),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.video_library_outlined), selectedIcon: Icon(Icons.video_library), label: 'Browse'),
            // Search has no outlined/filled pair in Material Icons.
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(
                icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: 'Downloads'),
          ],
        ),
      );
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
