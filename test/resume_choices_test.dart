import 'package:flick/addons.dart';
import 'package:flick/history.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/kit/route.dart';
import 'package:flick/playback.dart';
import 'package:flick/screens/player.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/screens/torrent.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _video = (id: 'tt1:2:3', title: 'Third episode', season: 2, episode: 3,
  released: null, thumbnail: null);
Meta _meta(String type) => (id: 'tt1', type: type, name: 'Test title', poster: null,
  background: null, logo: null, description: null, scope: null, releaseInfo: null, runtime: null,
  imdbRating: null, genres: <String>[], videos: [_video]);
final _source = Addon({'id': 'test', 'name': 'Test source', 'types': ['movie', 'series'],
  'resources': ['stream'], 'catalogs': []}, 'https://example.test');
AddonStream _stream(bool torrent) => (name: 'Test release', title: '1080p',
  infoHash: torrent ? '0123456789012345678901234567890123456789' : null, fileIdx: 0,
  url: torrent ? null : 'https://example.test/fresh.mp4', externalUrl: null,
  trackers: <String>[], filename: null, headers: <String, String>{}, subtitles: <Subtitle>[],
  videoSize: null, videoHash: null, bingeGroup: null);

class _Addons extends Addons {
  _Addons(this.torrent);
  final bool torrent;
  final requests = <String>[];
  @override
  Future<Meta> meta(String type, String id) async => _meta(type);
  @override
  List<Addon> streamSources(String type, String videoId) => [_source];
  @override
  Future<List<AddonStream>> streams(Addon addon, String type, String videoId) async {
    requests.add(videoId);
    return [_stream(torrent)];
  }
}

// Inspect route configuration before mounting the native player.
class _Routes extends NavigatorObserver {
  Widget? screen;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is EpisodeRoute) screen = route.builder(navigator!.context);
  }
}

void main() {
  final original = addons;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await saved.load();
    await history.load();
  });
  tearDown(() {
    addons = original;
    device.tv = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  for (final tv in [false, true]) {
    for (final type in ['movie', 'series']) {
      for (final torrent in [false, true]) {
        testWidgets('$type ${torrent ? 'torrent' : 'direct'} choices on ${tv ? 'TV' : 'phone'}', (tester) async {
          device.tv = tv;
          FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
          tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final id = type == 'movie' ? 'tt1' : _video.id;
          await history.save(WatchProgress(type: type, videoId: id, title: 'Test title',
            position: const Duration(seconds: 123), duration: const Duration(minutes: 20)));
          final fake = _Addons(torrent);
          addons = fake;
          final routes = _Routes();
          await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
            navigatorObservers: [routes], home: type == 'movie'
              ? const TitleScreen((id: 'tt1', type: 'movie', name: 'Test title', poster: null, scope: null, releaseInfo: null))
              : StreamsScreen(_meta(type), _video)));
          await tester.pumpAndSettle();
          expect(fake.requests, [id]);
          expect(find.text('Resume · 2:03'), findsOneWidget);
          await tester.ensureVisible(find.text('Start over'));
          await tester.pumpAndSettle();
          if (tv) {
            final choice = find.ancestor(of: find.text('Resume · 2:03'), matching: find.byType(FocusFrame)).first;
            final detector = find.descendant(of: choice, matching: find.byType(FocusableActionDetector));
            tester.widget<FocusableActionDetector>(detector).focusNode!.requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            await tester.pumpAndSettle();
            expect(FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<FocusFrame>(), tester.widget<FocusFrame>(
                find.ancestor(of: find.text('Start over'), matching: find.byType(FocusFrame)).first));
            await tester.sendKeyEvent(LogicalKeyboardKey.select);
          } else {
            await tester.tap(find.text('Start over'));
          }
          await tester.pumpAndSettle();
          expect(find.text('Choose a source to play from the beginning.'), findsOneWidget);
          expect(history.position(type, id), const Duration(seconds: 123));

          for (final startOver in [true, false]) {
            if (!startOver) {
              await tester.ensureVisible(find.text('Resume · 2:03'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Resume · 2:03'));
              await tester.pumpAndSettle();
            }
            final target = find.bySemanticsLabel(RegExp('1080p')).first;
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            await tester.tap(target);
            final screen = routes.screen;
            expect(screen, torrent ? isA<TorrentScreen>() : isA<PlayerScreen>());
            expect(torrent ? (screen as TorrentScreen).start : (screen as PlayerScreen).start,
              startOver ? Duration.zero : null);
            routes.navigator!.pop();
            await tester.pumpAndSettle();
            expect(history.position(type, id), const Duration(seconds: 123));
          }
          await history.save(WatchProgress(type: type, videoId: id, title: 'Test title',
            position: const Duration(minutes: 19), duration: const Duration(minutes: 20)));
          await tester.pumpAndSettle();
          expect(find.text('Resume · 2:03'), findsNothing);
          expect(find.text('Start over'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('Start over does not carry into Up Next', (tester) async {
    final routes = _Routes();
    await tester.pumpWidget(MaterialApp(navigatorObservers: [routes], home: const SizedBox()));
    final p = episodePlayback(_meta('series'), _video);
    final done = play(routes.navigator!.context, _stream(false), p, start: Duration.zero);
    expect((routes.screen as PlayerScreen).start, Duration.zero);
    const nextVideo = (id: 'tt1:2:4', title: 'Fourth episode', season: 2, episode: 4,
      released: null, thumbnail: null);
    routes.navigator!.pop(NextStream(_stream(false), episodePlayback(_meta('series'), nextVideo), _source));
    // Let play() consume the result and push the next route without mounting mpv.
    await tester.idle();
    expect((routes.screen as PlayerScreen).start, isNull);
    routes.navigator!.pop();
    await done;
    await tester.pumpAndSettle();
  });
}
