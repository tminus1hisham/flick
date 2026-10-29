
import 'package:flick/addons.dart';
import 'package:flick/kit/download_button.dart';
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

AddonStream _stream(String title, {String? infoHash = 'ed0afbc1', String? url, String? externalUrl, String? name}) => (
      name: name,
      title: title,
      infoHash: infoHash,
      fileIdx: null,
      url: url,
      externalUrl: externalUrl,
      trackers: const [],
      filename: null,
      headers: const {},
      subtitles: const [],
      videoSize: null,
      videoHash: null,
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
  setUp(() => describeStream = (s) => (
        quality: '1080p',
        seeders: s.title!.contains('unknown') ? null : 284,
        size: '812 MB',
        origin: '1337x',
        lines: [s.title!],
      ));

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

  testWidgets('only torrent streams get a download action, separate from the row that plays', (tester) async {
    await _open(
        tester,
        _Addons(_meta('movie'), sources: [_Addon('Northstar')], results: {
          'Northstar': [_stream('The.Kid.1921.1080p'), _stream('Direct', infoHash: null, url: 'https://cdn.example/kid.mp4')],
        }),
        'movie');

    expect(find.byType(DownloadButton), findsOneWidget);
    expect(find.bySemanticsLabel('Download'), findsOneWidget);
    expect(find.bySemanticsLabel('1080p, The.Kid.1921.1080p, 284 seeders, 812 MB, from 1337x'), findsOneWidget);
    expect(find.bySemanticsLabel('1080p, Direct, 284 seeders, 812 MB, from 1337x'), findsOneWidget);
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
