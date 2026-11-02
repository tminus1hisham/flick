import 'dart:convert';

import 'package:flick/addons.dart';
import 'package:flick/downloads.dart';
import 'package:flick/history.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/playback.dart';
import 'package:flick/queue.dart';
import 'package:flick/screens/continue_watching.dart';
import 'package:flick/screens/discover.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> manifest(String id) => {'id': id, 'name': id, 'version': '1.0.0',
  'types': ['series', 'movie'], 'resources': ['catalog', 'meta', 'stream'],
  'catalogs': [{'type': 'series', 'id': 'all', 'name': id}]};

void main() {
  final original = addons;
  late Addons client;
  late List<Uri> requests;
  late bool fail;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    requests = [];
    fail = false;
    client = Addons(client: MockClient((request) async {
      requests.add(request.url);
      if (fail) return http.Response('{}', 503);
      final path = request.url.path;
      final Object body;
      if (path.endsWith('/manifest.json')) {
        body = manifest(request.url.host);
      } else if (path.contains('/catalog/')) {
        body = {'metas': [{'id': 'show:opaque:parent', 'type': 'series', 'name': request.url.host}]};
      } else if (path.contains('/meta/')) {
        body = {'meta': {'id': 'show:opaque:parent', 'type': 'series', 'name': request.url.host,
          'videos': [{'id': 'independent-clip', 'title': 'First', 'season': 1, 'episode': 1},
            {'id': 'next-clip', 'title': 'Next', 'season': 1, 'episode': 2}]}};
      } else {
        body = {'streams': [{'url': 'https://media.test/fresh.mp4',
          'behaviorHints': {'bingeGroup': 'release'}}]};
      }
      return http.Response(jsonEncode(body), 200);
    }));
    await client.load();
    await client.add('https://north.test/secret-config/manifest.json');
    await client.add('https://south.test/manifest.json');
    addons = client;
    await history.load();
    await saved.load();
  });
  tearDown(() {
    addons = original;
    device.tv = false;
  });

  Future<MetaPreview> preview() async => (await client.catalog(
    client.catalogs.firstWhere((c) => c.addon.name == 'north.test'))).single;

  test('legacy addon configuration gets a persisted local scope on load', () async {
    final prefs = await SharedPreferences.getInstance();
    final records = jsonDecode(prefs.getString('addons')!) as List;
    for (final record in records) { (record as Map).remove('scopeId'); }
    await prefs.setString('addons', jsonEncode(records));
    await client.load();
    final scope = (await preview()).scope;
    await client.load();
    expect((await preview()).scope, scope);
    expect((jsonDecode(prefs.getString('addons')!) as List).every((r) => r['scopeId'] is String), isTrue);
  });

  test('provider migration is stable, credential free and distinct after reinstall', () async {
    final p = await preview();
    final first = p.scope!;
    await client.load();
    expect((await preview()).scope, first);
    final meta = await client.scopedMeta('series', p.id, first);
    final playback = episodePlayback(meta, meta.videos.first);
    await history.save(WatchProgress(type: playback.type, videoId: playback.videoId,
      scope: playback.scope, title: playback.title, position: const Duration(minutes: 2),
      duration: const Duration(minutes: 20)));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('viewingHistory'), isNot(contains('secret-config')));
    expect(prefs.getString('viewingHistory'), isNot(contains('https://')));
    final owner = client.active.firstWhere((a) => a.scopeId == first.provider);
    await client.remove(owner);
    requests.clear();
    await expectLater(client.scopedMeta('series', p.id, first), throwsA(isA<AddonException>()));
    expect(requests, isEmpty);
    await client.restore(owner);
    expect((await preview()).scope, first);
    await client.remove(owner);
    await client.add('https://north.test/reconfigured/manifest.json');
    expect((await preview()).scope, isNot(first));
  });

  test('offline records, movie queue and next episode preserve the content owner', () async {
    final p = await preview();
    final meta = await client.scopedMeta('series', p.id, p.scope);
    final playback = episodePlayback(meta, meta.videos.first);
    final stream = (await client.streams(client.active.last, 'series', playback.videoId)).single;
    final offline = StreamDownload.fromMetaData(StreamDownload(title: playback.title,
      playback: playback).toMetaData())!.playback;
    expect(offline.scope, p.scope);
    final legacy = Download(hash: 'hash', magnet: 'magnet', file: 0, playback: playback);
    expect(Download.fromJson(legacy.toJson()).playback.scope, p.scope);
    final next = await resolveNext(client.active.last, meta, meta.videos.last, stream.bingeGroup);
    expect((next as NextStream).playback.scope, p.scope);
    expect(next.playback.videoId, 'next-clip');
    final queued = QueuedMovie.fromJson(QueuedMovie.fromStream('custom-movie', 'Movie', null,
      client.active.last, stream, scope: p.scope).toJson());
    expect(moviePlayback(queued).scope, p.scope);
    await history.save(WatchProgress(type: playback.type, videoId: playback.videoId,
      scope: playback.scope, title: playback.title, position: const Duration(minutes: 2),
      duration: const Duration(minutes: 20)));
    await history.load();
    expect(history.position(offline.type, offline.videoId, scope: offline.scope), const Duration(minutes: 2));
  });

  for (final tv in [false, true]) {
    testWidgets('search retains colliding custom IDs and opens their owning catalog ($tv)', (tester) async {
      device.tv = tv;
      tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null, home: Scaffold(body:
        CatalogFeed.search(client.catalogs.where((c) => c.addon.name.endsWith('.test')).toList(),
          query: 'show', onClear: () {}))));
      await tester.pumpAndSettle();
      expect(find.text('north.test'), findsOneWidget);
      expect(find.text('south.test'), findsOneWidget);
      if (tv) {
        tester.widget<FocusFrame>(find.byWidgetPredicate((w) =>
          w is FocusFrame && w.semanticLabel == 'south.test')).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('south.test'));
      }
      await tester.pumpAndSettle();
      expect(tester.widget<TitleScreen>(find.byType(TitleScreen)).preview.scope!.provider,
        client.active.firstWhere((a) => a.name == 'south.test').scopeId);
      expect(requests.where((u) => u.path.contains('/meta/')).every((u) => u.host == 'south.test'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('custom Continue Watching uses exact owner and parent, with Retry ($tv)', (tester) async {
      device.tv = tv;
      tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final p = await preview();
      final progress = WatchProgress(type: 'series', videoId: 'independent-clip', scope: p.scope,
        title: p.name, position: const Duration(minutes: 2), duration: const Duration(minutes: 20));
      await history.save(progress);
      fail = true;
      await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), home: WatchSourcesScreen(progress)));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      requests.clear();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(tester.widget<StreamsScreen>(find.byType(StreamsScreen)).meta.scope, p.scope);
      expect(requests.where((u) => u.path.contains('/meta/')).single.host, 'north.test');
      expect(requests.where((u) => u.path.contains('/meta/')).single.pathSegments.last, 'show:opaque:parent.json');
      expect(requests.where((u) => u.path.contains('/stream/')).every((u) =>
        u.pathSegments.last == 'independent-clip.json'), isTrue);
      expect(find.text('Resume · 2:00'), findsOneWidget);
      expect(history.position('series', progress.videoId, scope: p.scope), const Duration(minutes: 2));
      expect(tester.takeException(), isNull);
    });
  }
}
