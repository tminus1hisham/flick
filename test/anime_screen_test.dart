import 'dart:async';
import 'dart:convert';

import 'package:flick/anime.dart';
import 'package:flick/screens/anime.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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

Future<void> pump(WidgetTester tester, Widget home, {double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 640);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: flickTheme(),
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 640),
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: home,
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('newer searches win when older responses arrive later', (
    tester,
  ) async {
    final first = Completer<List<AnimeCard>>(),
        second = Completer<List<AnimeCard>>();
    final anime = _Anime()
      ..find = (q) => q == 'first' ? first.future : second.future;
    await pump(tester, AnimeScreen(client: anime));
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
      await pump(tester, AnimeScreen(client: anime));
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
