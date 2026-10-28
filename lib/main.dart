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
  static const _tabs = [HomeScreen(), LibrariesScreen(), SearchScreen(), DownloadsScreen()];
  static const _titles = ['', 'Libraries', 'Search', 'Downloads'];

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
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.video_library_outlined), label: 'Libraries'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.download_outlined), label: 'Downloads'),
          ],
        ),
      );
}

class OfflineShell extends StatelessWidget {
  const OfflineShell({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Offline · Downloads'),
          actions: [
            const MagnetButton(),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Reconnect', onPressed: session.recheck),
          ],
        ),
        body: const DownloadsScreen(),
      );
}
