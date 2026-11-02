import 'dart:async';
import 'dart:convert';

import 'package:flick/addons.dart';
import 'package:flick/anime.dart';
import 'package:flick/history.dart';
import 'package:flick/kit/route.dart';
import 'package:flick/screens/player.dart';
import 'package:flick/screens/anime.dart';
import 'package:flick/screens/discover.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const card = (id: 20, title: 'Naruto', poster: null);
const episode = (
  animeId: 20,
  id: 'opaque_ID',
  number: 1,
  title: 'First episode',
);

AnimeResolution result({String url = 'https://cdn.example/master.m3u8'}) =>
    parseAnimeResolution(episode, {
      'tracks': [
        {
          'track': 'sub',
          'providers': [
            {
              'provider': 'animepahe',
              'downloads': [],
              'subtitles': [],
              'servers': [
                {
                  'server': 'main',
                  'headers': {'Referer': 'https://embed.example/'},
                  'streams': [
                    {'url': url, 'format': 'hls', 'quality': '720p'},
                  ],
                },
              ],
            },
          ],
        },
        {
          'track': 'dub',
          'providers': [
            {
              'provider': 'anikoto',
              'downloads': [],
              'subtitles': [],
              'servers': [],
            },
          ],
        },
      ],
    });

class _Anime extends Anime {
  Future<List<AnimeCard>> Function(String)? find;
  Future<List<AnimeEpisode>> Function(int)? list;
  Future<AnimeResolution> Function(AnimeEpisode)? source;
  int resolutions = 0;
  @override
  Future<List<AnimeCard>> search(String q) => find!(q);
  @override
  Future<List<AnimeEpisode>> episodes(int id) => list!(id);
  @override
  Future<AnimeResolution> resolve(AnimeEpisode e) {
    resolutions++;
    return source!(e);
  }
}

class _Catalogs extends Addons {
  final _addon = Addon({
    'id': 'kitsu-test',
    'name': 'Anime Kitsu',
    'resources': ['catalog', 'meta'],
    'types': ['anime', 'movie', 'series'],
    'catalogs': [
      {'type': 'anime', 'id': 'trending', 'name': 'Trending'},
      {'type': 'anime', 'id': 'airing', 'name': 'Airing', 'extra': [{'name': 'genre', 'options': ['Action', 'Romance']}]},
      {'type': 'series', 'id': 'latest', 'name': 'Latest episodes'},
    ],
  }, 'https://anime-kitsu.strem.fun');
  final requests = <(String, String, String?, int)>[];
  final genres = <String?>[];
  final metaRequests = <(String, String)>[];
  bool enabled = true;
  String itemType = 'series';
  Future<List<MetaPreview>>? page;

  void setCatalogsEnabled(bool value) {
    enabled = value;
    notifyListeners();
  }

  @override
  List<Catalog> get catalogs => enabled ? _addon.catalogs : [];

  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, String? genre, int skip = 0}) {
    requests.add((c.type, c.id, search, skip));
    genres.add(genre);
    return page ?? Future.value([
      if (skip == 0)
        (id: 'kitsu:11', type: itemType, name: 'Kitsu ${c.id}', poster: null, scope: null, releaseInfo: '2002'),
    ]);
  }

  @override
  Future<Meta> meta(String type, String id) async {
    metaRequests.add((type, id));
    return (
      id: id,
      type: type,
      name: 'Kitsu title',
      poster: null,
      background: null,
      logo: null,
      description: null,
      scope: null, releaseInfo: '2002',
      runtime: null,
      imdbRating: null,
      genres: const <String>[],
      trailers: const <Trailer>[],
      videos: const <Video>[],
    );
  }

  @override
  List<Addon> streamSources(String type, String videoId) => const [];
}

late _Catalogs _catalogs;

class _PlayerRoutes extends NavigatorObserver {
  PlayerScreen? player;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is EpisodeRoute) player = route.builder(navigator!.context) as PlayerScreen;
  }
}

Future<void> pump(WidgetTester tester, Widget home, {double scale = 1, bool still = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 640);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: flickTheme(),
      routes: {
        '/sources': (_) => Scaffold(
          appBar: AppBar(title: const Text('Sources')),
          body: const Text('Sources destination'),
        ),
      },
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 640),
          textScaler: TextScaler.linear(scale),
          disableAnimations: still,
        ),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => addons = _catalogs = _Catalogs());

  testWidgets('Miruro chooses mode before refreshing links; cancellation and failed opens retain progress', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await history.load();
    await history.save(const WatchProgress(type: 'anime', videoId: 'anilist:20:1', title: 'Naruto',
      position: Duration(seconds: 123), duration: Duration(minutes: 20)));
    addTearDown(history.clear);
    final anime = _Anime()..source = (_) async => result();
    addTearDown(anime.close);
    final routes = _PlayerRoutes();
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), navigatorObservers: [routes], home:
      AnimeSourcesScreen(card: card, episode: episode, anime: anime, cancel: () {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(anime.resolutions, 1);
    routes.navigator!.pop();
    await tester.pumpAndSettle();
    expect(anime.resolutions, 1);
    for (final over in [true, false]) {
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(over ? 'Start over' : 'Resume · 2:03'));
      await tester.idle();
      expect(routes.player?.start, over ? Duration.zero : null);
      expect(routes.player?.source, 'https://cdn.example/master.m3u8');
      routes.navigator!.pop();
      await tester.pumpAndSettle();
    }
    anime.source = (_) async => throw const AnimeException(AnimeError.unreachable);
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();
    expect(history.position('anime', 'anilist:20:1'), const Duration(seconds: 123));
    expect(find.text('Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty query shows the first anime catalog and chips switch the shared feed', (tester) async {
    await pump(tester, const AnimeTab());
    await tester.pumpAndSettle();
    expect(find.byType(CatalogFeed), findsOneWidget);
    expect(_catalogs.requests.single, ('anime', 'trending', null, 0));
    expect(find.text('Kitsu trending'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Trending')).selected, isTrue);
    expect(find.text('Latest episodes'), findsNothing);

    await tester.tap(find.text('Airing'));
    await tester.pumpAndSettle();
    expect(_catalogs.requests.last, ('anime', 'airing', null, 0));
    expect(find.text('Kitsu airing'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Airing')).selected, isTrue);
  });

  testWidgets('anime genre tabs filter the catalog and All genres clears it', (tester) async {
    await pump(tester, const AnimeTab());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Airing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    expect(_catalogs.genres.last, 'Action');
    expect(_catalogs.requests.last, ('anime', 'airing', null, 0));
    await tester.tap(find.text('All genres'));
    await tester.pumpAndSettle();
    expect(_catalogs.genres.last, isNull);
  });

  testWidgets('catalog loading uses the shared skeleton and clearing Miruro search restores the feed', (tester) async {
    final page = Completer<List<MetaPreview>>();
    _catalogs.page = page.future;
    final anime = _Anime()..find = (_) async => [card];
    await pump(tester, AnimeTab(client: anime));
    expect(find.byType(GridSkeleton), findsOneWidget);
    page.complete([
      (id: 'kitsu:11', type: 'series', name: 'Kitsu title', poster: null, scope: null, releaseInfo: null),
    ]);
    await tester.pumpAndSettle();
    final feed = tester.state(find.byType(CatalogFeed));

    await tester.enterText(find.byType(TextField), 'Naruto');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Naruto'), findsOneWidget);
    expect(find.text('Kitsu title'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Kitsu title'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Naruto'), findsNothing);
    expect(tester.state(find.byType(CatalogFeed)), same(feed));
    expect(_catalogs.requests, hasLength(1));
  });

  testWidgets('catalog posters open Title with the item type, mapping leftover anime to series', (tester) async {
    for (final type in ['series', 'movie', 'anime']) {
      _catalogs.itemType = type;
      await pump(tester, AnimeTab(key: ValueKey(type)), still: true);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kitsu trending'));
      await tester.pumpAndSettle();
      expect(find.byType(TitleScreen), findsOneWidget);
      expect(_catalogs.metaRequests.last, (type == 'anime' ? 'series' : type, 'kitsu:11'));
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('no enabled anime catalog offers one inline Sources link and still permits Miruro search', (tester) async {
    final anime = _Anime()..find = (_) async => [card];
    await pump(tester, AnimeTab(client: anime));
    await tester.pumpAndSettle();
    _catalogs.setCatalogsEnabled(false);
    await tester.pumpAndSettle();
    expect(find.text('No anime catalogs are switched on.'), findsOneWidget);
    expect(find.byType(CatalogNotice), findsOneWidget);
    expect(find.byType(CatalogFeed), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sources'));
    await tester.pumpAndSettle();
    expect(find.text('Sources destination'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Naruto');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Naruto'), findsOneWidget);
    expect(find.text('No anime catalogs are switched on.'), findsNothing);
  });

  testWidgets('catalog chips and posters fit at larger text sizes with reduced motion', (tester) async {
    await pump(tester, const AnimeTab(), scale: 1.3, still: true);
    await tester.pumpAndSettle();
    expect(find.text('Kitsu trending'), findsOneWidget);
    final heroMode = tester.widget<HeroMode>(
      find.ancestor(of: find.byType(CatalogFeed), matching: find.byType(HeroMode)).first,
    );
    expect(heroMode.enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('newer searches win when older responses arrive later', (
    tester,
  ) async {
    final first = Completer<List<AnimeCard>>(),
        second = Completer<List<AnimeCard>>();
    final anime = _Anime()
      ..find = (q) => q == 'first' ? first.future : second.future;
    await pump(tester, AnimeTab(client: anime));
    await tester.enterText(find.byType(TextField), 'first');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.enterText(find.byType(TextField), 'second');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    second.complete([card]);
    await tester.pumpAndSettle();
    expect(find.text('Naruto'), findsOneWidget);
    first.complete([(id: 1, title: 'Stale title', poster: null)]);
    await tester.pumpAndSettle();
    expect(find.text('Stale title'), findsNothing);
    expect(find.text('Naruto'), findsOneWidget);
  });

  testWidgets(
    'leaving the episode list drops late results and cancels browser access',
    (tester) async {
      final episodes = Completer<List<AnimeEpisode>>();
    final anime = _Anime();
    anime.find = (_) async => [card];
    anime.list = (_) => episodes.future;
      await pump(tester, AnimeTab(client: anime));
      await tester.enterText(find.byType(TextField), 'Naruto');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Naruto'));
      await tester.pumpAndSettle();
      expect(find.text('Finding episodes…'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      episodes.complete([episode]);
      await tester.pumpAndSettle();
      expect(find.text('First episode'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sub is default; choosing dub shows its own providers and download availability',
    (tester) async {
      final anime = _Anime()..source = (_) async => result();
      addTearDown(anime.close);
      await pump(
        tester,
        AnimeSourcesScreen(
          card: card,
          episode: episode,
          anime: anime,
          cancel: () {},
        ),
      );
      expect(find.text('animepahe'), findsOneWidget);
      expect(find.text('anikoto'), findsNothing);
      expect(find.text('No provider download URL returned.'), findsOneWidget);
      await tester.tap(find.text('Dub'));
      await tester.pump();
      expect(find.text('anikoto'), findsOneWidget);
      expect(find.text('animepahe'), findsNothing);
      expect(
        find.text('No playable media URLs for this provider.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'copy resolves a fresh URL and copies exactly its media headers',
    (tester) async {
      final next = Completer<AnimeResolution>();
      final anime = _Anime()..source = (_) async => result();
      addTearDown(anime.close);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(
        tester,
        AnimeSourcesScreen(
          card: card,
          episode: episode,
          anime: anime,
          cancel: () {},
        ),
      );
      anime.source = (_) => next.future;
      await tester.ensureVisible(find.text('Copy URL + headers'));
      await tester.tap(find.text('Copy URL + headers'));
      await tester.pump();
      expect(copied, isNull);
      expect(anime.resolutions, 2);
      next.complete(result(url: 'https://fresh.example/master.m3u8'));
      await tester.pumpAndSettle();
      expect(jsonDecode(copied!), {
        'url': 'https://fresh.example/master.m3u8',
        'headers': {'referer': 'https://embed.example/'},
      });
      expect(find.text('Copied. Links may expire.'), findsOneWidget);
    },
  );

  testWidgets('changing language drops an in-flight copy result', (
    tester,
  ) async {
    final next = Completer<AnimeResolution>();
    final anime = _Anime()..source = (_) async => result();
    addTearDown(anime.close);
    var writes = 0, cancellations = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') writes++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(
      tester,
      AnimeSourcesScreen(
        card: card,
        episode: episode,
        anime: anime,
        cancel: () {
          cancellations++;
        },
      ),
    );
    anime.source = (_) => next.future;
    await tester.ensureVisible(find.text('Copy URL'));
    await tester.tap(find.text('Copy URL'));
    await tester.pump();
    await tester.ensureVisible(find.text('Dub'));
    await tester.tap(find.text('Dub'));
    await tester.pump();
    next.complete(result());
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(cancellations, 1);
    expect(find.text('anikoto'), findsOneWidget);
  });

  testWidgets('blocked source explains failure and can retry', (tester) async {
    final anime = _Anime()
      ..source = (_) async => throw const AnimeException(AnimeError.blocked);
    addTearDown(anime.close);
    await pump(
      tester,
      AnimeSourcesScreen(
        card: card,
        episode: episode,
        anime: anime,
        cancel: () {},
      ),
    );
    expect(find.text('Miruro is blocking this connection.'), findsOneWidget);
    anime.source = (_) async => result();
    await tester.tap(find.text('Refresh sources'));
    await tester.pumpAndSettle();
    expect(find.text('animepahe'), findsOneWidget);
  });

  testWidgets('provider list and link actions fit at larger text sizes', (
    tester,
  ) async {
    final anime = _Anime()..source = (_) async => result();
    addTearDown(anime.close);
    await pump(
      tester,
      AnimeSourcesScreen(
        card: card,
        episode: episode,
        anime: anime,
        cancel: () {},
      ),
      scale: 1.3,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
