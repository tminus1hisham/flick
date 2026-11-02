import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flick/downloads.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/kit/tv_surface.dart';
import 'package:flick/playback.dart';
import 'package:flick/screens/downloads.dart' as http;
import 'package:flick/screens/native_downloads.dart' as native;
import 'package:flick/screens/torrent.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const Playback _playback = (title: 'A television download', subtitle: 'S1 E2 · Second episode',
  logo: null, poster: null, type: 'series', videoId: 'tt123:1:2', season: 1, episode: 2,
  scope: null, meta: null);

class _Downloads extends Downloads {
  final calls = <String>[];
  @override
  Future<void> pause(Object r) async => calls.add('pause');
  @override
  Future<void> resume(Object r) async => calls.add('resume');
  @override
  Future<void> retry(TaskRecord r) async => calls.add('retry');
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  device.tv = true;
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(() { device.tv = false; tester.view.reset(); });
  await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: true), shortcuts: tvShortcuts,
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
      textScaler: const TextScaler.linear(1.3), disableAnimations: true), child: child!),
    home: Scaffold(body: TvSurface(child: child))));
  await tester.pump();
}

int _rings(WidgetTester tester) => tester.widgetList<CustomPaint>(find.byType(CustomPaint))
  .where((w) => w.foregroundPainter is FocusRing).length;

void main() {
  for (final status in [TaskStatus.running, TaskStatus.paused, TaskStatus.failed]) {
    testWidgets('TV HTTP $status action activates once with a visible ring', (tester) async {
      final old = downloads;
      final fake = _Downloads();
      downloads = fake;
      addTearDown(() { downloads = old; fake.dispose(); });
      const stream = StreamDownload(title: 'A television download', playback: _playback);
      final task = DownloadTask(url: 'https://example.test/video', allowPause: true);
      await _pump(tester, ListView(children: [http.DownloadRow(
        record: TaskRecord(task, status, 0.5, 100), poster: File('missing'), stream: stream)]));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_rings(tester), 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(fake.calls, [status == TaskStatus.running ? 'pause' : status == TaskStatus.paused ? 'resume' : 'retry']);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      final menu = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.text('Delete download'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(menu));
      expect(fake.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV native download menu restores focus after Back', (tester) async {
    final download = Download(hash: 'hash', magnet: 'magnet', file: 0, playback: _playback,
      path: 'missing', state: DownloadState.done);
    var plays = 0;
    await _pump(tester, ListView(children: [native.DownloadRow(download: download, onPlay: (_) => plays++)]));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(plays, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    final menu = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('Delete download'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_rings(tester), greaterThan(0));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, same(menu));
    expect(_rings(tester), 1);
    expect(tester.takeException(), isNull);
  });

  for (final automatic in [false, true]) {
    testWidgets('TV torrent ${automatic ? 'startup uses episode label' : 'file choices reveal and activate'}', (tester) async {
      final root = Directory.systemTemp.createTempSync('flick-tv-test');
      addTearDown(() => root.deleteSync(recursive: true));
      const channel = MethodChannel('flick/torrent');
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final added = Completer<void>(), opening = Completer<String>();
      int? selected;
      messenger.setMockMethodCallHandler(paths, (_) async => root.path);
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'add': added.complete(); return 1;
          case 'status': return {'name': 'raw/season-pack', 'peers': 4, 'rate': 1024, 'hasMetadata': true};
          case 'files': return [for (var n = 0; n < 12; n++)
            {'index': n, 'name': 'raw/season-pack/Episode-$n.mkv', 'size': 1000 - n}];
          case 'stream': selected = (call.arguments as Map)['file'] as int; return opening.future;
          default: return null;
        }
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(paths, null);
      });
      await _pump(tester, TorrentScreen('magnet', title: _playback.title, playback: _playback,
        fileIdx: automatic ? 2 : null));
      for (var i = 0; i < 50 && !added.isCompleted; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(added.isCompleted, isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      if (automatic) {
        expect(selected, 2);
        expect(find.text('Opening S1 E2 · Second episode'), findsOneWidget);
        expect(find.text('raw/season-pack/Episode-2.mkv'), findsNothing);
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab); // Back
        for (var i = 0; i < 8; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(selected, greaterThan(0));
        final row = tester.getRect(find.text('raw/season-pack/Episode-$selected.mkv'));
        expect(row.top, greaterThan(0));
        expect(row.bottom, lessThan(540));
        expect(_rings(tester), greaterThan(0));
        expect(find.text('raw/season-pack'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      opening.complete('http://localhost/video');
      await tester.pump();
    });
  }
}
