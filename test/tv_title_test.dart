import 'dart:async';

import 'package:flick/addons.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _source = Addon({
  'id': 'test', 'name': 'Test source', 'types': ['movie', 'series'], 'resources': ['stream'], 'catalogs': [],
}, 'https://example.test');
const _video = (id: 'kitsu:1:1', title: 'First episode', season: 1, episode: 1,
  released: null, thumbnail: null);
const _stream = (name: 'Test release', title: '1080p Blu-ray', infoHash: 'abc', fileIdx: 0,
  url: null, externalUrl: null, trackers: <String>[], filename: null, headers: <String, String>{},
  subtitles: <Subtitle>[], videoSize: null, videoHash: null, bingeGroup: null);
Meta _meta({String type = 'series', List<Video> videos = const [_video]}) => (
  id: 'kitsu:1', type: type, name: 'A very long title that takes two lines on television',
  poster: null, background: null, logo: null, description: 'A description of this title. ' * 40,
  scope: null, releaseInfo: '2026', runtime: '24 min', imdbRating: null, genres: ['Animation'], trailers: const <Trailer>[], videos: videos,
);

class _Addons extends Addons {
  _Addons(this.metadata);
  final Future<Meta> metadata;
  List<Addon> sources = [_source];
  Future<List<AddonStream>> response = Future.value([_stream]);
  final requests = <String>[];
  final responses = <String, Future<List<AddonStream>>>{};
  @override
  Future<Meta> meta(String type, String id) => metadata;
  @override
  List<Addon> streamSources(String type, String videoId) => sources;
  @override
  Future<List<AddonStream>> streams(Addon addon, String type, String videoId) {
    requests.add(videoId);
    return responses[addon.id] ?? response;
  }
}

void main() {
  final original = addons;
  tearDown(() {
    addons = original;
    device.tv = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<void> pump(WidgetTester tester, _Addons fake, {String type = 'series', Size size = const Size(960, 540),
      bool settle = true, double scale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    await saved.load();
    addons = fake;
    device.tv = true;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: true), shortcuts: tvShortcuts,
      home: TitleScreen((id: 'kitsu:1', type: type, name: 'Preview title', poster: null, scope: null, releaseInfo: '2026'))));
    if (settle) { await tester.pumpAndSettle(); }
    else { await tester.pump(); await tester.pump(); }
  }

  String? focused() => FocusManager.instance.primaryFocus?.context
      ?.findAncestorWidgetOfExactType<FocusFrame>()?.semanticLabel;
  String? focusedText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? text;
    void visit(Element element) {
      if (text != null) return;
      if (element.widget is Text) { text = (element.widget as Text).data; }
      else { element.visitChildren(visit); }
    }
    (context as Element).visitChildren(visit);
    return text;
  }
  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
  Future<void> back(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')), (_) {});
    await tester.pumpAndSettle();
  }

  testWidgets('series opens on season; episode streams stay in the pane; Back restores episode focus', (tester) async {
    final fake = _Addons(Future.value(_meta()));
    await pump(tester, fake);
    expect(focusedText(), 'S1');
    expect(fake.requests, isEmpty);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), contains('First episode'));
    await key(tester, LogicalKeyboardKey.select);
    expect(fake.requests, ['kitsu:1:1']);
    expect(find.text('Streams'), findsOneWidget);
    expect(focused(), contains('1080p'));
    await back(tester);
    expect(find.text('Episodes'), findsOneWidget);
    expect(focused(), contains('First episode'));
    expect(find.byType(TitleScreen), findsOneWidget);
  });

  testWidgets('movie loading slot hands focus to stream, not filters or download', (tester) async {
    final response = Completer<List<AddonStream>>();
    final fake = _Addons(Future.value(_meta(type: 'movie')))..response = response.future;
    await pump(tester, fake, type: 'movie');
    expect(focused(), 'Loading streams');
    response.complete([_stream]);
    await tester.pumpAndSettle();
    expect(focused(), contains('1080p'));
    expect(fake.requests, ['kitsu:1']);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Download torrent');
  });

  testWidgets('late metadata does not steal focus from Back', (tester) async {
    final metadata = Completer<Meta>();
    await pump(tester, _Addons(metadata.future));
    expect(focused(), 'Loading title');
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'Back');
    metadata.complete(_meta());
    await tester.pumpAndSettle();
    expect(focused(), 'Back');
  });

  testWidgets('metadata error has reachable recovery', (tester) async {
    final metadata = Completer<Meta>();
    await pump(tester, _Addons(metadata.future));
    metadata.completeError(AddonException(AddonError.unreachable));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't connect"), findsOneWidget);
    expect(focusedText(), 'Try again');
  });

  testWidgets('no stream sources opens on Add a source', (tester) async {
    await pump(tester, _Addons(Future.value(_meta(type: 'movie')))..sources = [], type: 'movie');
    expect(focusedText(), 'Add a source');
  });


  testWidgets('empty episodes focus Refresh', (tester) async {
    await pump(tester, _Addons(Future.value(_meta(videos: []))));
    expect(find.text('No episodes listed yet'), findsOneWidget);
    expect(focusedText(), 'Refresh');
  });

  for (final servicesOnly in [false, true]) {
  testWidgets('source replies retain focus within the chosen source (services-only: $servicesOnly)', (tester) async {
    final slow = Completer<List<AddonStream>>();
    final fast = Completer<List<AddonStream>>();
    final second = Addon({'id': 'second', 'name': 'Second source', 'types': ['movie'],
      'resources': ['stream']}, 'https://second.example');
    final fake = _Addons(Future.value(_meta(type: 'movie')))
      ..sources = [_source, second];
    fake.responses[_source.id] = slow.future;
    fake.responses[second.id] = fast.future;
    await pump(tester, fake, type: 'movie');
    // Move deliberately to the second provider's loading slot.
    final slots = find.byWidgetPredicate((w) => w is FocusFrame && w.semanticLabel == 'Loading streams');
    final detector = find.descendant(of: slots.at(2), matching: find.byType(FocusableActionDetector));
    tester.widget<FocusableActionDetector>(detector).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    slow.complete(servicesOnly ? [(name: 'Service', title: 'Watch online', infoHash: null, fileIdx: null,
      url: null, externalUrl: 'https://example.test/watch', trackers: <String>[], filename: null,
      headers: <String, String>{}, subtitles: <Subtitle>[], videoSize: null, videoHash: null, bingeGroup: null)]
      : [_stream, (name: 'Another release', title: '720p', infoHash: 'def', fileIdx: 0,
      url: null, externalUrl: null, trackers: <String>[], filename: null, headers: <String, String>{},
      subtitles: <Subtitle>[], videoSize: null, videoHash: null, bingeGroup: null)]);
    await tester.pumpAndSettle();
    expect(focused(), 'Loading streams', reason: 'another source must not steal focus');
    fast.complete([(name: 'Chosen release', title: 'Second provider 4K', infoHash: 'ghi', fileIdx: 0,
      url: null, externalUrl: null, trackers: <String>[], filename: null, headers: <String, String>{},
      subtitles: <Subtitle>[], videoSize: null, videoHash: null, bingeGroup: null)]);
    await tester.pumpAndSettle();
    expect(focused(), contains('Second provider'));
    expect(tester.takeException(), isNull);
  });

  }

  testWidgets('source failure focuses Retry and the remote retries it', (tester) async {
    final response = Completer<List<AddonStream>>();
    final fake = _Addons(Future.value(_meta(type: 'movie')))..response = response.future;
    await pump(tester, fake, type: 'movie');
    response.completeError(AddonException(AddonError.unreachable));
    await tester.pumpAndSettle();
    expect(focusedText(), 'Retry');
    fake.response = Future.value([_stream]);
    await key(tester, LogicalKeyboardKey.select);
    expect(focused(), contains('1080p'));
    expect(fake.requests.length, 2);
  });

  for (final size in [const Size(960, 540), const Size(900, 500)]) {
    testWidgets('long title and 1.3x text fit $size; only right pane scrolls', (tester) async {
      await pump(tester, _Addons(Future.value(_meta())), size: size, scale: 1.3);
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.text(_meta().name));
      final episode = tester.getRect(find.text('E1 · First episode'));
      expect(title.left, FlickTv.railColumn + FlickTv.contentGap);
      expect(episode.left, greaterThan(title.right));
      expect(tester.getRect(find.byIcon(Icons.favorite_border_rounded)).bottom, lessThanOrEqualTo(size.height - FlickTv.insetV));
    });
  }
}
