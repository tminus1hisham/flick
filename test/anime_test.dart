import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flick/anime.dart';
import 'package:flick/miruro_browser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const episode = (
  animeId: 20,
  id: 'opaque-catalog_ID',
  number: 1,
  title: 'First',
);
const episodeBody = {
  'data': [
    {'episode_number': 1, 'title': 'First'},
  ],
};
const catalogBody = {
  'data': [
    {
      'id': 'opaque-catalog_ID',
      'external_ids': {
        'anilist': ['20'],
      },
    },
  ],
};
const searchBody = {
  'data': {
    'Page': {
      'media': [
        {
          'id': 20,
          'title': {'romaji': 'NARUTO', 'english': 'Naruto'},
        },
      ],
    },
  },
};

http.Response json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);
http.Response binary(Object body) {
  final compressed = gzip.encode(utf8.encode(jsonEncode(body)));
  final key = utf8.encode('miruro/catalog');
  return http.Response.bytes(
    [
      for (var i = 0; i < compressed.length; i++)
        compressed[i] ^ key[i % key.length],
    ],
    200,
    headers: {'content-type': 'application/octet-stream'},
  );
}

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/anime/$name.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, Object> playback({List<Object> downloads = const []}) => {
  'tracks': [
    {
      'track': 'sub',
      'providers': [
        {
          'provider': 'animepahe',
          'downloads': downloads,
          'subtitles': [
            {'file': 'https://subs.example/en.vtt', 'language': 'en'},
          ],
          'servers': [
            {
              'server': 'first',
              'headers': {
                'Referer': 'https://embed.example/',
                'Cookie': 'session=secret',
                'Authorization': 'secret',
              },
              'streams': [
                {
                  'url': 'https://cdn.example/master.m3u8?signature=x',
                  'format': 'hls',
                  'quality': '1080p',
                },
              ],
            },
            {
              'server': 'second',
              'headers': {
                'referer': 'https://second.example/',
                'X-Bad': 'a\nb',
              },
              'streams': [
                {
                  'url': 'https://cdn.example/movie.mp4',
                  'format': 'mp4',
                  'headers': {'Referer': 'https://own.example/'},
                },
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
          'servers': [],
          'downloads': [],
          'subtitles': [],
        },
      ],
    },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('current catalog transport and plain JSON decode identically', () async {
    expect(await decodeAnimeBody(binary(episodeBody)), episodeBody);
    expect(await decodeAnimeBody(json(episodeBody)), episodeBody);
  });

  test('malformed and oversized bodies are changed responses', () async {
    for (final raw in [
      '<html>error</html>',
      'broken',
      '[]',
      'a' * (2 * 1024 * 1024 + 1),
    ]) {
      await expectLater(
        decodeAnimeBody(http.Response(raw, 200)),
        throwsA(
          isA<AnimeException>().having(
            (e) => e.kind,
            'kind',
            AnimeError.changed,
          ),
        ),
      );
    }
    await expectLater(
      decodeAnimeBody(binary({'data': 'a' * (8 * 1024 * 1024)})),
      throwsA(isA<AnimeException>()),
    );
  });

  test(
    'redacted device fixtures decode episodes, providers and download pages',
    () async {
      final episodes = parseAnimeEpisodes(
        20,
        'opaque-catalog_ID',
        fixture('episodes'),
      );
      expect(episodes.first.number, 1);
      expect(episodes.first.id, 'opaque-catalog_ID');
      final result = parseAnimeResolution(episodes.first, fixture('playback'));
      expect(
        result.variants.map((v) => v.language),
        containsAll(['sub', 'ssub', 'dub']),
      );
      expect(result.variants.first.streams.first.kind, AnimeLinkKind.hls);
      expect(result.variants.first.downloads.first.kind, AnimeLinkKind.page);
      expect(
        await decodeAnimeBody(binary(fixture('playback'))),
        fixture('playback'),
      );
    },
  );

  test(
    'episode numbers remain distinct and malformed entries are not invented',
    () {
      final episodes = parseAnimeEpisodes(20, 'opaque-catalog_ID', {
        'data': [
          {'episode_number': 1, 'title': 'First'},
          {'episode_number': 2},
          {'episode_number': null},
          {'episode_number': 0},
        ],
      });
      expect(episodes.first, episode);
      expect(episodes[1].title, 'Episode 2');
      expect(episodes, hasLength(2));
      expect(
        () => parseAnimeEpisodes(20, 'id', {}),
        throwsA(isA<AnimeException>()),
      );
    },
  );

  test(
    'headers are per server, case-normalized, and never inherited by downloads or subtitles',
    () {
      final result = parseAnimeResolution(
        episode,
        playback(
          downloads: [
            {'url': 'https://pahe.example/download'},
          ],
        ),
      );
      final variant = result.variants.first;
      expect(variant.streams.first.headers, {
        'referer': 'https://embed.example/',
      });
      expect(variant.streams[1].headers, {'referer': 'https://own.example/'});
      expect(variant.streams[1].kind, AnimeLinkKind.file);
      expect(variant.downloads.single.headers, isEmpty);
      expect(variant.downloads.single.kind, AnimeLinkKind.page);
      expect(
        animeStream(variant, variant.streams.first).subtitles.single.url,
        'https://subs.example/en.vtt',
      );
      expect(
        animeStream(variant, variant.streams.first).headers.keys,
        isNot(contains('cookie')),
      );
    },
  );

  test(
    'missing downloads remain absent and invalid stream URLs are dropped',
    () {
      expect(
        parseAnimeResolution(episode, playback()).variants.first.downloads,
        isEmpty,
      );
      final body = playback();
      final tracks = body['tracks'] as List;
      tracks.add({
        'track': 'sub',
        'providers': [
          {
            'provider': 'bad',
            'servers': [
              {
                'server': 'bad',
                'streams': [
                  {'url': 'javascript:alert(1)', 'format': 'hls'},
                  {'url': 'file:///tmp/movie.mp4', 'format': 'mp4'},
                  {'url': 'https://embed.example/watch'},
                ],
              },
            ],
          },
        ],
      });
      expect(
        parseAnimeResolution(episode, body).variants.last.streams,
        isEmpty,
      );
      expect(
        () => parseAnimeResolution(episode, {}),
        throwsA(isA<AnimeException>()),
      );
    },
  );

  test(
    'search uses AniList and catalog mapping requires an exact external ID',
    () async {
      final paths = <String>[];
      final anime = Anime(
        client: MockClient((r) async {
          paths.add(r.url.path);
          expect(
            r.headers.keys.map((s) => s.toLowerCase()),
            isNot(contains('cookie')),
          );
          if (r.url.host == 'graphql.anilist.co') {
            expect(jsonDecode(r.body)['variables']['search'], 'Naruto');
            return json(searchBody);
          }
          if (r.url.path.endsWith('/episodes')) {
            expect(r.url.path, '/api/v1/anime/opaque-catalog_ID/episodes');
            expect(r.url.queryParameters, {'limit': '10000'});
            return binary(episodeBody);
          }
          expect(r.url.queryParameters, {'q': 'NARUTO', 'limit': '15'});
          return binary({
            'data': [
              {
                'id': 'wrong',
                'title': {'english': 'Naruto'},
                'external_ids': {
                  'anilist': ['1735'],
                },
              },
              ...(catalogBody['data'] as List),
            ],
          });
        }),
      );
      addTearDown(anime.close);
      expect((await anime.search(' Naruto ')).single.id, 20);
      expect((await anime.episodes(20)).single, episode);
      expect(paths.length, 3);
    },
  );

  test(
    'an ambiguous or absent catalog identity cannot select the wrong season',
    () async {
      for (final entries in [
        [],
        [...(catalogBody['data'] as List), ...(catalogBody['data'] as List)],
      ]) {
        final anime = Anime(
          client: MockClient(
            (r) async => r.url.host == 'graphql.anilist.co'
                ? json(searchBody)
                : json({'data': entries}),
          ),
        );
        await anime.search('Naruto');
        await expectLater(
          anime.episodes(20),
          throwsA(
            isA<AnimeException>().having(
              (e) => e.kind,
              'kind',
              AnimeError.unavailable,
            ),
          ),
        );
        anime.close();
      }
    },
  );

  test(
    'blocked access falls back once, and browser bytes retain their content type',
    () async {
      var browserCalls = 0;
      final anime = Anime(
        client: MockClient((_) async => http.Response('', 403)),
        browser: (uri) async {
          browserCalls++;
          expect(uri.path, '/api/v1/anime/opaque-catalog_ID/episodes/1/play');
          return binary(playback());
        },
      );
      addTearDown(anime.close);
      expect(
        (await anime.resolve(episode)).variants.first.provider,
        'animepahe',
      );
      expect(browserCalls, 1);
    },
  );

  test(
    'successful browser access is reused without another blocked direct request',
    () async {
      var direct = 0, browser = 0;
      final anime = Anime(
        client: MockClient((_) async {
          direct++;
          return http.Response('', 403);
        }),
        browser: (_) async {
          browser++;
          return binary(playback());
        },
      );
      addTearDown(anime.close);
      await anime.resolve(episode);
      await anime.resolve(episode);
      expect(direct, 1);
      expect(browser, 2); // Fresh source data is still fetched for each action.
    },
  );

  test(
    'failed reused session resets transport preference for an explicit retry',
    () async {
      var direct = 0, browser = 0;
      final anime = Anime(
        client: MockClient((_) async {
          direct++;
          return http.Response('', 403);
        }),
        browser: (_) async {
          browser++;
          if (browser == 2) throw const AnimeException(AnimeError.unreachable);
          return binary(playback());
        },
      );
      addTearDown(anime.close);
      await anime.resolve(episode);
      await expectLater(anime.resolve(episode), throwsA(isA<AnimeException>()));
      await anime.resolve(episode);
      expect(direct, 2);
      expect(browser, 3);
    },
  );

  test('browser remaining blocked stops without retrying', () async {
    var calls = 0;
    final anime = Anime(
      client: MockClient((_) async => http.Response('', 403)),
      browser: (_) async {
        calls++;
        return http.Response('', 403);
      },
    );
    addTearDown(anime.close);
    await expectLater(
      anime.resolve(episode),
      throwsA(
        isA<AnimeException>().having((e) => e.kind, 'kind', AnimeError.blocked),
      ),
    );
    expect(calls, 1);
  });

  test('challenge HTML with HTTP 200 triggers browser access', () async {
    final anime = Anime(
      client: MockClient(
        (_) async => http.Response(
          '<title>Just a moment...</title>',
          200,
          headers: {'content-type': 'text/html'},
        ),
      ),
      browser: (_) async => binary(playback()),
    );
    addTearDown(anime.close);
    expect((await anime.resolve(episode)).variants, isNotEmpty);
  });

  test('network, missing episode and schema failures are distinct', () async {
    for (final pair in [
      (404, AnimeError.unavailable),
      (500, AnimeError.unreachable),
      (200, AnimeError.changed),
    ]) {
      final anime = Anime(client: MockClient((_) async => json({}, pair.$1)));
      await expectLater(
        anime.resolve(episode),
        throwsA(isA<AnimeException>().having((e) => e.kind, 'kind', pair.$2)),
      );
      anime.close();
    }
    final offline = Anime(
      client: MockClient((_) async => throw const SocketException('offline')),
    );
    addTearDown(offline.close);
    await expectLater(
      offline.resolve(episode),
      throwsA(
        isA<AnimeException>().having(
          (e) => e.kind,
          'kind',
          AnimeError.unreachable,
        ),
      ),
    );
  });

  test('closing the client drops a late browser answer', () async {
    final response = Completer<http.Response>(), entered = Completer<void>();
    final anime = Anime(
      client: MockClient((_) async => http.Response('', 403)),
      browser: (_) {
        entered.complete();
        return response.future;
      },
    );
    final check = expectLater(
      anime.resolve(episode),
      throwsA(
        isA<AnimeException>().having(
          (e) => e.kind,
          'kind',
          AnimeError.cancelled,
        ),
      ),
    );
    await entered.future;
    anime.close();
    response.complete(binary(playback()));
    await check;
  });

  test('browser cancellation ignores late channel replies', () async {
    const channel = MethodChannel('flick/miruro');
    final response = Completer<Object?>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call.method);
          return call.method == 'request'
              ? response.future
              : Future.value(null);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final browser = MiruroBrowser();
    final check = expectLater(
      browser.request(
        Uri.parse('${miruroOrigins.first}/api/v1/anime?q=Naruto&limit=15'),
      ),
      throwsA(
        isA<AnimeException>().having(
          (e) => e.kind,
          'kind',
          AnimeError.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await browser.cancel();
    response.complete({'status': 200, 'body': base64Encode(utf8.encode('{}'))});
    await check;
    expect(calls, ['request', 'cancel']);
  });

  test(
    'browser bridge rejects other origins, schemes, and non-catalog paths',
    () async {
      final browser = MiruroBrowser();
      for (final url in [
        'file:///api/v1/anime',
        'http://www.miruro.to/api/v1/anime',
        'https://evil.example/api/v1/anime',
        'https://www.miruro.to/api/account',
        'https://www.miruro.to/api/v1/anime#fragment',
      ]) {
        await expectLater(
          browser.request(Uri.parse(url)),
          throwsA(
            isA<AnimeException>().having(
              (e) => e.kind,
              'kind',
              AnimeError.changed,
            ),
          ),
        );
      }
    },
  );
}
