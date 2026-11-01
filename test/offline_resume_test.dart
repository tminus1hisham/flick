import 'dart:io';

import 'package:flick/downloads.dart';
import 'package:flick/history.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/playback.dart';
import 'package:flick/screens/downloads.dart';
import 'package:flick/screens/player.dart';
import 'package:flick/screens/resume.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/torrent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Playback _playback = (title: 'Offline movie', subtitle: null, logo: null, poster: null,
  type: 'movie', videoId: 'tt123', season: null, episode: null, meta: null);

class _Routes extends NavigatorObserver {
  PlayerScreen? player;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is MaterialPageRoute) {
      final screen = route.builder(navigator!.context);
      if (screen is PlayerScreen) player = screen;
    }
  }
}

class _LocalDownloads extends Downloads {
  _LocalDownloads(this.path);
  final String? path;
  @override
  Future<String?> localPath(String id) async => path;
}

void main() {
  final original = downloads;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await history.load();
  });
  tearDown(() { downloads = original; device.tv = false; });

  for (final tv in [false, true]) {
    testWidgets('resume choices preserve progress and support cancellation, tv=$tv', (tester) async {
      device.tv = tv;
      await history.save(const WatchProgress(type: 'movie', videoId: 'tt123', title: 'Offline movie',
        position: Duration(seconds: 123), duration: Duration(minutes: 20)));
      bool? choice;
      await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
        builder: (_, child) => MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(1.3)), child: child!),
        home: Builder(builder: (context) => TextButton(onPressed: () async {
          choice = await chooseStartOver(context, _playback);
        }, child: const Text('Open')))));
      for (final over in [false, true]) {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Resume · 2:03'), findsOneWidget);
        if (tv) {
          if (over) await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else {
          await tester.tap(find.text(over ? 'Start over' : 'Resume · 2:03'));
        }
        await tester.pumpAndSettle();
        expect(choice, over);
        expect(history.position('movie', 'tt123'), const Duration(seconds: 123));
      }
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Start over'))).pop();
      await tester.pumpAndSettle();
      expect(choice, isNull);
      await history.clear();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(choice, false);
      expect(find.text('Start over'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('native offline playback passes start over without removing history', (tester) async {
    final file = File('${Directory.systemTemp.createTempSync('resume').path}/movie.mp4')..writeAsStringSync('fixture');
    addTearDown(() => file.parent.deleteSync(recursive: true));
    downloads = Downloads()..items = [Download(hash: 'hash', magnet: 'magnet', file: 0,
      playback: _playback, path: file.path, state: DownloadState.done)];
    addTearDown(downloads.dispose);
    await history.save(const WatchProgress(type: 'movie', videoId: 'tt123', title: 'Offline movie',
      position: Duration(seconds: 123), duration: Duration(minutes: 20)));
    final routes = _Routes();
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), navigatorObservers: [routes],
      home: const Scaffold(body: DownloadsScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline movie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start over'));
    // Inspect the route before mounting native mpv.
    await tester.idle();
    expect(routes.player?.source, file.path);
    expect(routes.player?.start, Duration.zero);
    expect(history.position('movie', 'tt123'), const Duration(seconds: 123));
    routes.navigator!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('legacy download row passes both modes and reports missing files before asking', (tester) async {
    await history.save(const WatchProgress(type: 'movie', videoId: 'tt123', title: 'Offline movie',
      position: Duration(seconds: 123), duration: Duration(minutes: 20)));
    final download = TorrentDownload(KeptTorrent(id: 1, infoHash: 'hash', magnet: 'magnet', file: 0,
      dir: 'downloads', titleJson: const StreamDownload(title: 'Offline movie', playback: _playback).toMetaData(),
      name: 'movie.mp4', size: 100, done: true))
      ..info = const TorrentProgress(downloaded: 100, total: 100, done: true);
    final local = _LocalDownloads('offline.mp4');
    downloads = local;
    addTearDown(local.dispose);
    final routes = _Routes();
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), navigatorObservers: [routes], home: Scaffold(
      body: DownloadRow.torrent(download: download, poster: File('missing-poster')))));
    for (final over in [true, false]) {
      await tester.tap(find.text('Offline movie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(over ? 'Start over' : 'Resume · 2:03'));
      await tester.idle();
      expect(routes.player?.source, 'offline.mp4');
      expect(routes.player?.start, over ? Duration.zero : null);
      routes.navigator!.pop();
      await tester.pumpAndSettle();
    }
    final missing = _LocalDownloads(null);
    downloads = missing;
    addTearDown(missing.dispose);
    await tester.tap(find.text('Offline movie'));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded file is missing. Delete it and download again.'), findsOneWidget);
    expect(find.text('Start over'), findsNothing);
    expect(history.position('movie', 'tt123'), const Duration(seconds: 123));
  });
}
