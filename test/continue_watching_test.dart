import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent;

import 'package:flick/addons.dart';
import 'package:flick/anime.dart';
import 'package:flick/history.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/screens/anime.dart';
import 'package:flick/screens/continue_watching.dart';
import 'package:flick/screens/discover.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _video = (id: 'tt1:2:3', title: 'Third episode', season: 2, episode: 3,
  released: null, thumbnail: null);
const _source = {'id': 'test', 'name': 'Test source', 'types': ['movie', 'series'],
  'resources': ['stream'], 'catalogs': []};

class _Addons extends Addons {
  bool fail = false, missing = false;
  Completer<Meta>? pending;
  final metas = <(String, String)>[], videos = <String>[];
  @override
  List<Catalog> get catalogs => [];
  @override
  Future<Meta> meta(String type, String id) async {
    metas.add((type, id));
    if (pending != null) return pending!.future;
    if (fail) throw StateError('Offline');
    return (id: id, type: type, name: 'Saved title', poster: null,
      background: null, logo: null, description: null, scope: null, releaseInfo: null, runtime: null,
      imdbRating: null, genres: <String>[], videos: missing ? <Video>[] : <Video>[
        _video, (id: 'kitsu:42:3', title: 'Kitsu episode', season: 1, episode: 3,
          released: null, thumbnail: null)]);
  }
  @override
  List<Addon> streamSources(String type, String videoId) => [Addon(_source, 'https://example.test')];
  @override
  Future<List<AddonStream>> streams(Addon addon, String type, String videoId) async {
    videos.add(videoId);
    return [];
  }
}

class _Anime extends Anime {
  final ids = <int>[], resolved = <AnimeEpisode>[];
  @override
  Future<List<AnimeEpisode>> episodes(int id) async {
    ids.add(id);
    return [(animeId: id, id: 'fresh-catalog', number: 3, title: 'Fresh episode')];
  }
  @override
  Future<AnimeResolution> resolve(AnimeEpisode episode) async {
    resolved.add(episode);
    return (episode: episode, variants: <AnimeVariant>[]);
  }
}

WatchProgress progress({String type = 'series', String id = 'tt1:2:3', String title = 'Saved title',
  int seconds = 123}) => WatchProgress(type: type, videoId: id, title: title, subtitle: 'Saved episode',
    position: Duration(seconds: seconds), duration: const Duration(minutes: 20));

void main() {
  final original = addons;
  late _Addons fake;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await history.load();
    await saved.load();
    addons = fake = _Addons();
  });
  tearDown(() {
    addons = original;
    device.tv = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<void> pump(WidgetTester tester, Widget home, {bool tv = false}) async {
    device.tv = tv;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
      home: home));
    await tester.pumpAndSettle();
  }

  for (final tv in [false, true]) {
    testWidgets('Discover resumes exact episode with fresh source lookup (${tv ? 'TV' : 'phone'})', (tester) async {
      final semantics = tester.ensureSemantics();
      await history.save(progress());
      await pump(tester, const Scaffold(body: DiscoverScreen()), tv: tv);
      expect(find.text('Continue Watching'), findsOneWidget);
      final target = find.bySemanticsLabel('Saved title, Saved episode, resume at 2:03');
      if (tv) {
        final detector = find.descendant(of: find.widgetWithText(FocusFrame, 'Saved title').first,
          matching: find.byType(FocusableActionDetector));
        tester.widget<FocusableActionDetector>(detector).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        final node = tester.getSemantics(target);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        tester.binding.performSemanticsAction(SemanticsActionEvent(
          type: SemanticsAction.tap, nodeId: node.id, viewId: tester.view.viewId));
      }
      await tester.pumpAndSettle();
      expect(find.byType(StreamsScreen), findsOneWidget);
      expect(tester.widget<StreamsScreen>(find.byType(StreamsScreen)).video.id, _video.id);
      expect(fake.metas, [('series', 'tt1')]);
      expect(fake.videos, [_video.id]);
      Navigator.of(tester.element(find.byType(StreamsScreen))).pop();
      await tester.pumpAndSettle();
      expect(history.position('series', _video.id), const Duration(seconds: 123));
      await history.save(progress(seconds: 1140));
      await tester.pumpAndSettle();
      expect(find.text('Continue Watching'), findsNothing);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  for (final identity in [('movie', 'tt1', 'tt1'), ('series', 'kitsu:42:3', 'kitsu:42')]) {
    testWidgets('resolves ${identity.$2} with the correct metadata identity', (tester) async {
      await pump(tester, WatchSourcesScreen(progress(type: identity.$1, id: identity.$2)));
      expect(fake.metas, [(identity.$1, identity.$3)]);
      expect(fake.videos, [identity.$2]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing episode and offline failures preserve progress and can retry', (tester) async {
    await history.save(progress());
    fake.fail = true;
    await pump(tester, WatchSourcesScreen(progress()));
    expect(find.text('Retry'), findsOneWidget);
    fake.fail = false;
    fake.missing = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(StreamsScreen), findsNothing);
    expect(fake.videos, isEmpty);
    fake.missing = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(StreamsScreen), findsOneWidget);
    expect(fake.metas.length, 3);
    expect(history.position('series', _video.id), const Duration(seconds: 123));
  });

  testWidgets('Miruro refreshes catalog episode identity before resolving sources', (tester) async {
    final anime = _Anime();
    addTearDown(anime.close);
    await pump(tester, WatchSourcesScreen(progress(type: 'anime', id: 'anilist:20:3'), anime: anime));
    expect(find.byType(AnimeSourcesScreen), findsOneWidget);
    expect(anime.ids, [20]);
    expect(anime.resolved.single.id, 'fresh-catalog');
    expect(anime.resolved.single.number, 3);
    expect(fake.metas, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV can reveal and select later checkpoints at larger text', (tester) async {
    for (var i = 0; i < 12; i++) {
      await history.save(progress(id: 'tt1:2:$i', title: 'Video $i'));
    }
    await pump(tester, const Scaffold(body: ContinueWatching()), tv: true);
    final detectors = find.byType(FocusableActionDetector);
    tester.widget<FocusableActionDetector>(detectors.first).focusNode!.requestFocus();
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    final focused = FocusManager.instance.primaryFocus!.context!
      .findAncestorWidgetOfExactType<FocusFrame>()!;
    expect(focused.semanticLabel, startsWith('Video 1,'));
    expect(tester.getRect(find.text('Video 1')).overlaps(const Rect.fromLTWH(0, 0, 960, 540)), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Back during metadata lookup safely ignores its late result', (tester) async {
    fake.pending = Completer<Meta>();
    await pump(tester, const Scaffold(body: ContinueWatching()));
    final context = tester.element(find.byType(ContinueWatching));
    Navigator.push(context, MaterialPageRoute(builder: (_) => WatchSourcesScreen(progress())));
    await tester.pumpAndSettle();
    expect(find.text('Finding sources…'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    fake.pending!.completeError(StateError('late failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
