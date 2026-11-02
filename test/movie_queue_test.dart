import 'dart:async';

import 'package:flick/addons.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/kit/route.dart';
import 'package:flick/playback.dart';
import 'package:flick/queue.dart';
import 'package:flick/screens/movie_queue.dart';
import 'package:flick/screens/player.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/screens/torrent.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _provider = Addon({'id': 'test', 'name': 'Source', 'types': ['movie', 'series'],
  'resources': ['stream'], 'catalogs': []}, 'https://queue.test');
AddonStream _stream({String url = 'https://queue.test/fresh', bool torrent = false, String release = 'Release'}) => (
  name: '1080p', title: release, infoHash: torrent ? '0123456789012345678901234567890123456789' : null,
  fileIdx: torrent ? 0 : null, url: torrent ? null : url, externalUrl: null, trackers: <String>[],
  filename: null, headers: <String, String>{}, subtitles: <Subtitle>[], videoSize: null, videoHash: null, bingeGroup: null);
QueuedMovie _movie(String id) => QueuedMovie.fromStream(id, 'Movie $id', null, _provider, _stream());

class _Addons extends Addons {
  int requests = 0;
  bool fail = false;
  bool enabled = true;
  Future<List<AddonStream>>? pending;
  List<AddonStream> results = [_stream()];
  @override
  List<Addon> get active => enabled ? [_provider] : [];
  @override
  List<Addon> streamSources(String type, String videoId) => active;
  @override
  Future<Meta> meta(String type, String id) async => (id: id, type: type, name: 'Movie $id',
    poster: null, background: null, logo: null, description: null, releaseInfo: null,
    runtime: null, imdbRating: null, genres: <String>[], videos: <Video>[]);
  @override
  Future<List<AddonStream>> streams(Addon addon, String type, String videoId) async {
    requests++;
    if (fail) throw StateError('offline');
    return pending ?? results;
  }
}

class _Routes extends NavigatorObserver {
  Widget? screen;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is EpisodeRoute) screen = route.builder(navigator!.context);
  }
}

void main() {
  final original = addons;
  late _Addons fake;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await movieQueue.load();
    await history.load();
    await saved.load();
    addons = fake = _Addons();
  });
  tearDown(() { addons = original; device.tv = false; });

  Future<void> pump(WidgetTester tester, Widget home, {bool tv = false, NavigatorObserver? observer}) async {
    device.tv = tv;
    tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
      navigatorObservers: observer == null ? [] : [observer], home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('fresh matching source returns a choice without consuming pending movie', (tester) async {
    final item = _movie('tt1');
    await movieQueue.add(item);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
    final choice = chooseQueuedMovie(key.currentContext!, item);
    await tester.pumpAndSettle();
    expect(fake.requests, 1);
    expect(find.byType(MovieQueueScreen), findsNothing);
    expect((await choice)?.stream.url, 'https://queue.test/fresh');
    expect(fake.requests, 1);
    expect(movieQueue.items, [item]);
  });

  testWidgets('failed lookup, ambiguity, explicit source choice and cancellation retain queue', (tester) async {
    final item = _movie('tt1');
    await movieQueue.add(item);
    fake.fail = true;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), navigatorKey: key, home: const SizedBox()));
    final choice = chooseQueuedMovie(key.currentContext!, item);
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(movieQueue.items, [item]);
    fake.fail = false;
    fake.results = [_stream(url: 'https://queue.test/new-a'), _stream(url: 'https://queue.test/new-b')];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('chosen source changed'), findsOneWidget);
    await tester.tap(find.text('1080p · Release').last);
    await tester.pumpAndSettle();
    expect((await choice)?.stream.url, 'https://queue.test/new-b');
    expect(movieQueue.items, [item]);
    fake.enabled = false;
    final cancelled = chooseQueuedMovie(key.currentContext!, item);
    await tester.pumpAndSettle();
    expect(find.text('Choose another source'), findsOneWidget);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(await cancelled, isNull);
    expect(movieQueue.items, [item]);
  });

  testWidgets('late source lookup after Back cannot launch playback', (tester) async {
    final item = _movie('tt1');
    await movieQueue.add(item);
    final pending = Completer<List<AddonStream>>();
    fake.pending = pending.future;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const SizedBox()));
    final choice = chooseQueuedMovie(key.currentContext!, item);
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    pending.complete([_stream()]);
    await tester.pumpAndSettle();
    expect(await choice, isNull);
    expect(movieQueue.items, [item]);
    expect(tester.takeException(), isNull);
  });

  for (final torrent in [false, true]) {
    testWidgets('${torrent ? 'torrent' : 'direct'} startup retains pending until confirmed started', (tester) async {
      final item = _movie('tt1');
      await movieQueue.add(item);
      final routes = _Routes();
      await pump(tester, const SizedBox(), observer: routes);
      var done = play(routes.navigator!.context, _stream(torrent: torrent), moviePlayback(item), addon: _provider);
      expect(movieQueue.items, [item]);
      routes.navigator!.pop();
      await done;
      await tester.pumpAndSettle();
      expect(movieQueue.items, [item]);
      done = play(routes.navigator!.context, _stream(torrent: torrent), moviePlayback(item), addon: _provider);
      final started = torrent ? (routes.screen as TorrentScreen).onStarted : (routes.screen as PlayerScreen).onStarted;
      expect(started, isNotNull);
      started!();
      await tester.idle();
      expect(movieQueue.items, isEmpty);
      routes.navigator!.pop();
      await done;
      await tester.pumpAndSettle();
    });
  }

  testWidgets('movie handoff uses selected source and start choice without changing episode routing', (tester) async {
    final routes = _Routes();
    await pump(tester, const SizedBox(), observer: routes);
    final first = _movie('tt1');
    final second = QueuedMovie.fromStream('tt2', 'Second movie', null, _provider, _stream(), start: Duration.zero);
    await movieQueue.add(second);
    final done = play(routes.navigator!.context, _stream(), moviePlayback(first), addon: _provider);
    routes.navigator!.pop(MovieNext((item: second, addon: _provider, stream: _stream(url: 'https://queue.test/second'))));
    await tester.idle();
    final player = routes.screen as PlayerScreen;
    expect(player.playback?.videoId, 'tt2');
    expect(player.source, 'https://queue.test/second');
    expect(player.start, Duration.zero);
    expect(player.next, isNull);
    expect(movieQueue.items, [second]);
    routes.navigator!.pop();
    await done;
    await tester.pumpAndSettle();
    expect(movieQueue.items, [second]);
  });

  testWidgets('offline player results continue through the shared movie queue handoff', (tester) async {
    final routes = _Routes();
    await pump(tester, const SizedBox(), observer: routes);
    await continueMovieQueue(routes.navigator!.context, null);
    expect(routes.screen, isNull);
    final item = _movie('tt2');
    await movieQueue.add(item);
    final done = continueMovieQueue(routes.navigator!.context,
      MovieNext((item: item, addon: _provider, stream: _stream())));
    final player = routes.screen as PlayerScreen;
    expect(player.playback?.videoId, item.id);
    expect(movieQueue.items, [item]);
    player.onStarted!();
    await tester.idle();
    expect(movieQueue.items, isEmpty);
    routes.navigator!.pop();
    await done;
    await tester.pumpAndSettle();
  });

  for (final tv in [false, true]) {
    testWidgets('queue order, pinned Back and clear confirmation fit ${tv ? 'TV' : 'phone'} at 1.3x', (tester) async {
      await movieQueue.add(_movie('tt1'));
      await movieQueue.add(_movie('tt2'));
      await pump(tester, const MovieQueueScreen(), tv: tv);
      await tester.tap(find.byTooltip('Move up Movie tt2'));
      await tester.pumpAndSettle();
      expect(movieQueue.items.map((m) => m.id), ['tt2', 'tt1']);
      if (tv) expect(FocusManager.instance.primaryFocus?.debugLabel, 'Playback queue Back');
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(movieQueue.items, hasLength(2));
      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(movieQueue.items, isEmpty);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('movie sources add to playback queue separately from download on ${tv ? 'TV' : 'phone'}', (tester) async {
      await pump(tester, const TitleScreen((id: 'tt1', type: 'movie', name: 'Movie tt1', poster: null, releaseInfo: null)), tv: tv);
      await tester.ensureVisible(find.byTooltip('Add to playback queue'));
      await tester.tap(find.byTooltip('Add to playback queue'));
      await tester.pumpAndSettle();
      expect(movieQueue.items.single.id, 'tt1');
      await tester.tap(find.byTooltip('Already in playback queue'));
      await tester.pumpAndSettle();
      expect(movieQueue.items, hasLength(1));
      expect(find.text('Already in playback queue.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
