
import 'dart:async';
import 'dart:convert';

import 'package:flick/addons.dart';
import 'package:flick/downloads.dart';
import 'package:flick/playback.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Addon implements Addon {
  _Addon(this.name);
  @override
  final String name;
  @override
  String get id => name;
  @override
  String get base => 'https://$name.example';
  @override
  bool get bundled => false;
  @override
  bool get locked => false;
  @override
  bool serves(String resource, String type, String id) => true;
  @override
  List<Catalog> get catalogs => const [];
  @override
  String get capability => 'Streams';
}

/// Answers from [results] by addon name: a stream list, or an error to throw.
class _Addons extends Addons {
  _Addons(this.m, {this.sources = const [], this.results = const {}});
  final Meta m;
  final List<Addon> sources;
  final Map<String, Object> results;

  @override
  Future<Meta> meta(String type, String id) async => m;
  @override
  List<Addon> streamSources(String type, String videoId) => sources;
  @override
  Future<List<AddonStream>> streams(Addon a, String type, String videoId) async =>
      switch (results[a.name]) { final List<AddonStream> l => l, final e => throw e! };
}

class _Downloads extends Downloads {
  final requests = <({String url, Map<String, String> headers, StreamDownload data})>[];
  Completer<void>? pending;
  var fail = false;

  @override
  Future<void> enqueueStream({
    required String url,
    Map<String, String> headers = const {},
    required String title,
    String? poster,
    required Playback playback,
  }) async {
    requests.add((url: url, headers: headers,
        data: StreamDownload(title: title, poster: poster, playback: playback)));
    if (pending != null) await pending!.future;
    if (fail) throw StateError('Queue unavailable');
  }
}

AddonStream _stream(String title, {
  String? infoHash = 'ed0afbc1',
  String? externalUrl,
  String? name,
  String? url,
  Map<String, String> headers = const {},
}) => (
      name: name,
      title: title,
      infoHash: infoHash,
      fileIdx: null,
      url: url,
      externalUrl: externalUrl,
      trackers: const [],
      filename: null,
      headers: headers,
      subtitles: const [],
      videoSize: null,
      videoHash: null,
      bingeGroup: null,
    );

Meta _meta(String type, [List<Video> videos = const []]) => (
      id: 'tt1',
      type: type,
      name: 'Rick and Morty',
      poster: null,
      background: null,
      logo: null,
      description: null,
      releaseInfo: '2013',
      runtime: null,
      imdbRating: null,
      genres: const ['Animation'],
      videos: videos,
    );

Future<void> _open(WidgetTester tester, Addons fake, String type) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addons = fake;
  await tester.pumpWidget(MaterialApp(
    theme: flickTheme(),
    home: TitleScreen((id: 'tt1', type: type, name: 'Rick and Morty', poster: null, releaseInfo: null)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final originalAddons = addons;
  final originalDownloads = downloads;
  final originalDescribe = describeStream;

  setUp(() => describeStream = (s) => (
        quality: '1080p',
        seeders: s.title!.contains('unknown') ? null : 284,
        size: '812 MB',
        origin: '1337x',
        lines: [s.title!],
      ));

  tearDown(() {
    addons = originalAddons;
    downloads = originalDownloads;
    describeStream = originalDescribe;
  });

  test('stream filenames sanitize titles and keep the URL extension without its query', () {
    expect(streamDownloadFilename('  Rick: Morty / Pilot?  ', 'https://cdn.example/video.MKV?token=secret#part'),
        'Rick_ Morty _ Pilot_.MKV');
    expect(streamDownloadFilename('Episode', 'https://cdn.example/video.mp4', season: 4, episode: 2),
        'Episode S04E02.mp4');
    expect(streamDownloadFilename('Special', 'https://cdn.example/video.webm', season: 0, episode: 100),
        'Special S00E100.webm');
  });

  test('stream filenames use MP4 when the URL has no extension', () {
    expect(streamDownloadFilename('Film', 'https://cdn.example/play?file=film.mkv'), 'Film.mp4');
    expect(streamDownloadFilename('Film', 'https://cdn.example/video/'), 'Film.mp4');
    expect(streamDownloadFilename('Film', 'https://cdn.example/video'), 'Film.mp4');
    expect(streamDownloadFilename('Film', 'https://cdn.example/video.mp4', season: 1), 'Film.mp4');
  });

  test('stream filenames handle empty, reserved and long titles safely', () {
    expect(streamDownloadFilename(' ... ', 'https://cdn.example/video'), 'Video.mp4');
    expect(streamDownloadFilename('CON', 'https://cdn.example/video'), '_CON.mp4');
    expect(streamDownloadFilename('nul.txt', 'https://cdn.example/video'), '_nul.txt.mp4');
    expect(streamDownloadFilename('A\\B<C>D"E|F*G\u0000.', 'https://cdn.example/video'),
        'A_B_C_D_E_F_G_.mp4');
    final title = List.filled(200, '😀').join();
    final name = streamDownloadFilename(title, 'https://cdn.example/video');
    expect(name, '${List.filled(160, '😀').join()}.mp4');
    expect(name.contains('\uFFFD'), isFalse);
  });

  test('stream metadata round trips episode playback without online Up Next', () {
    final meta = _meta('series', [
      (id: 'tt1:4:2', title: 'The Old Man and the Seat', season: 4, episode: 2,
          released: null, thumbnail: null),
    ]);
    final p = episodePlayback(meta, meta.videos.single);
    final data = StreamDownload(title: p.title, poster: 'https://images.example/poster.jpg', playback: p);
    final encoded = data.toMetaData();
    final decoded = StreamDownload.fromMetaData(encoded)!;

    expect(decoded.title, data.title);
    expect(decoded.poster, data.poster);
    expect(decoded.playback, (
      title: p.title,
      subtitle: p.subtitle,
      type: p.type,
      videoId: p.videoId,
      season: p.season,
      episode: p.episode,
      meta: null,
    ));
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    expect((json['playback'] as Map).containsKey('meta'), isFalse);
    expect(json.containsKey('headers'), isFalse);
    expect(json.containsKey('url'), isFalse);
  });

  test('stream metadata round trips a movie and leaves Jellyfin metadata alone', () {
    const Playback p = (
      title: 'The Kid',
      subtitle: null,
      type: 'movie',
      videoId: 'tt123',
      season: null,
      episode: null,
      meta: null,
    );
    const data = StreamDownload(title: 'The Kid', playback: p);
    final decoded = StreamDownload.fromMetaData(data.toMetaData())!;

    expect(decoded.title, 'The Kid');
    expect(decoded.poster, isNull);
    expect(decoded.playback, p);
    expect(StreamDownload.fromMetaData(jsonEncode({'Id': 'jellyfin-id', 'Name': 'Film'})), isNull);
  });

  testWidgets('a movie groups streams per source, and a failing source keeps the others', (tester) async {
    await _open(
        tester,
        _Addons(_meta('movie'), sources: [_Addon('Northstar'), _Addon('Open Reel')], results: {
          'Northstar': [_stream('The.Kid.1921.1080p')],
          'Open Reel': AddonException(AddonError.unreachable),
        }),
        'movie');

    expect(find.text('Northstar'), findsWidgets); // group heading + filter chip
    expect(find.text('The.Kid.1921.1080p'), findsOneWidget);
    expect(find.text("Open Reel didn't answer"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
  });

  testWidgets('unknown seeders read "—", never 0', (tester) async {
    await _open(
        tester,
        _Addons(_meta('movie'),
            sources: [_Addon('Northstar')], results: {'Northstar': [_stream('unknown seeders')]}),
        'movie');

    expect(find.textContaining('—'), findsOneWidget);
    expect(find.textContaining(' 0'), findsNothing);
    expect(find.bySemanticsLabel('1080p, unknown seeders, 812 MB, from 1337x'), findsOneWidget);
  });

  testWidgets('no stream sources asks to add one', (tester) async {
    await _open(tester, _Addons(_meta('movie')), 'movie');

    expect(find.text('Install a stream source to find playable links'), findsOneWidget);
    expect(find.text('Add a source'), findsOneWidget);
  });

  testWidgets('an externalUrl stream is a where-to-watch row, not a stream found', (tester) async {
    await _open(
        tester,
        _Addons(_meta('movie'), sources: [_Addon('WatchHub')], results: {
          'WatchHub': [_stream('Rent · Buy', name: 'Rakuten TV', infoHash: null, externalUrl: 'https://rakuten.tv')],
        }),
        'movie');

    expect(find.text('Where to watch'), findsOneWidget);
    expect(find.text('Rakuten TV'), findsOneWidget);
    expect(find.text('WatchHub · Opens another app or website.'), findsOneWidget);
    expect(find.bySemanticsLabel('Rakuten TV, Rent · Buy. Opens another app or website.'), findsOneWidget);
    expect(find.text('No streams for this movie'), findsOneWidget);
  });

  testWidgets('only plain URL streams show an accessible 48 dp download button', (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(
        tester,
        _Addons(_meta('movie'), sources: [_Addon('Northstar')], results: {
          'Northstar': [
            _stream('Direct file', infoHash: null, url: 'https://cdn.example/video.mp4'),
            _stream('Torrent'),
            _stream('Mixed torrent', url: 'https://cdn.example/mixed.mp4'),
            _stream('Service', infoHash: null, externalUrl: 'https://service.example'),
            _stream('Mixed service', infoHash: null, url: 'https://cdn.example/offer.mp4',
                externalUrl: 'https://service.example/offer'),
          ],
        }),
        'movie');

    expect(find.byTooltip('Download'), findsOneWidget);
    expect(find.bySemanticsLabel('Download'), findsOneWidget);
    final size = tester.getSize(find.widgetWithIcon(IconButton, Icons.download_outlined));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    semantics.dispose();
  });

  testWidgets('download tap passes stream headers and shows queued state without opening playback', (tester) async {
    final fake = _Downloads()..pending = Completer<void>();
    downloads = fake;
    await _open(
        tester,
        _Addons(_meta('movie'), sources: [_Addon('Northstar')], results: {
          'Northstar': [
            _stream('Direct file', infoHash: null, url: 'https://cdn.example/video.mp4',
                headers: const {'Referer': 'https://source.example'}),
          ],
        }),
        'movie');

    await tester.tap(find.byTooltip('Download'));
    await tester.pump();

    expect(fake.requests, hasLength(1));
    expect(fake.requests.single.url, 'https://cdn.example/video.mp4');
    expect(fake.requests.single.headers, {'Referer': 'https://source.example'});
    expect(fake.requests.single.data.title, 'Rick and Morty');
    expect(fake.requests.single.data.playback.videoId, 'tt1');
    expect(find.text('Queuing…'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.download_outlined)).onPressed, isNull);

    fake.pending!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Queuing…'), findsNothing);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.check)).onPressed, isNull);
    expect(fake.requests, hasLength(1));
    expect(find.byType(TitleScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed download queue shows inline feedback and can retry', (tester) async {
    final fake = _Downloads()..fail = true;
    downloads = fake;
    await _open(
        tester,
        _Addons(_meta('movie'), sources: [_Addon('Northstar')], results: {
          'Northstar': [_stream('Direct file', infoHash: null, url: 'https://cdn.example/video.mp4')],
        }),
        'movie');

    await tester.tap(find.byTooltip('Download'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't queue download. Try again."), findsOneWidget);
    expect(find.text('Queued'), findsNothing);
    fake.fail = false;
    await tester.tap(find.byTooltip('Download'));
    await tester.pumpAndSettle();

    expect(fake.requests, hasLength(2));
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text("Couldn't queue download. Try again."), findsNothing);
  });

  testWidgets('episode download retains season, episode and canonical video identity', (tester) async {
    final fake = _Downloads();
    downloads = fake;
    const Video video = (
      id: 'tt1:4:2', title: 'The Old Man and the Seat', season: 4, episode: 2,
      released: null, thumbnail: null,
    );
    final meta = _meta('series', [video]);
    addons = _Addons(meta, sources: [_Addon('Northstar')], results: {
      'Northstar': [_stream('Direct episode', infoHash: null, url: 'https://cdn.example/episode.mkv')],
    });
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: StreamsScreen(meta, video)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Download'));
    await tester.pumpAndSettle();

    final p = fake.requests.single.data.playback;
    expect(p.videoId, 'tt1:4:2');
    expect(p.season, 4);
    expect(p.episode, 2);
    expect(p.subtitle, 'S4 E2 · The Old Man and the Seat');
    expect(find.text('Queued'), findsOneWidget);
  });

  testWidgets('a series shows season chips and episodes; a future episode is not tappable', (tester) async {
    Video ep(String id, int s, int e, String title, DateTime released) =>
        (id: id, title: title, season: s, episode: e, released: released, thumbnail: null);
    await _open(
        tester,
        _Addons(_meta('series', [
          ep('tt1:1:1', 1, 1, 'Pilot', DateTime(2013, 12, 2)),
          ep('tt1:4:2', 4, 2, 'The Old Man and the Seat', DateTime(2019, 11, 17)),
          ep('tt1:4:3', 4, 3, 'One Crew over the Crewcoo', DateTime(2099, 11, 12)),
        ])),
        'series');

    expect(find.widgetWithText(ChoiceChip, 'S1'), findsOneWidget);
    expect(find.text('E1 · Pilot'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'S4'));
    await tester.pumpAndSettle();
    expect(find.text('E2 · The Old Man and the Seat'), findsOneWidget);
    expect(find.text('Airs 12 Nov'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel(RegExp('Airs 12 Nov'))),
        isSemantics(hasEnabledState: true, isEnabled: false));

    await tester.tap(find.text('Airs 12 Nov'));
    await tester.pumpAndSettle();
    expect(find.text('Streams'), findsNothing);

    await tester.tap(find.text('E2 · The Old Man and the Seat'));
    await tester.pumpAndSettle();
    expect(find.text('Streams'), findsOneWidget);
    expect(find.text('Rick and Morty · S4 E2'), findsOneWidget);
  });
}
