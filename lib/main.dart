import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'screens/discover.dart';
import 'screens/sources.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
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
        // Discover's search field is its header and it keeps clear of the status bar itself; the bottom inset
        // was the navigation bar's job, so the grid now stops above the system bar here.
        home: const Scaffold(body: SafeArea(top: false, child: DiscoverScreen())),
      );
}
