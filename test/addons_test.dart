import 'dart:convert';

import 'package:flick/addons.dart';
import 'package:flick/torrent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

AddonStream stream({
  String? name,
  String? title,
  String? infoHash,
  List<String> trackers = const [],
  String? filename,
}) =>
    (
      name: name,
      title: title,
      infoHash: infoHash,
      fileIdx: null,
      url: null,
      externalUrl: null,
      trackers: trackers,
      filename: filename,
      headers: const {},
      subtitles: const [],
      videoSize: null,
      videoHash: null,
      bingeGroup: null,
    );

Map<String, dynamic> manifest(String id, {List<Object> resources = const ['stream']}) =>
    {'id': id, 'name': id, 'version': '1.0.0', 'resources': resources, 'types': ['movie', 'series'], 'catalogs': []};

/// Fresh [Addons] over [handler], loaded from [prefs].
Future<Addons> loaded(Future<http.Response> Function(http.Request) handler,
    [Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final a = Addons(client: MockClient(handler));
  await a.load();
  return a;
}

// No charset header: JSON is UTF-8 regardless.
http.Response json(Object body, [int status = 200]) => http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  const hash = 'ED0AFBC184168FCDD36BBB083C9EB304672B321D';
  const tracker = 'udp://tracker.opentrackr.org:1337/announce';

  test('magnetFor builds a valid magnet whose trackers round-trip', () {
    final m = magnetFor(stream(
        name: 'PDM', title: 'The Kid (1921)\n💾 1 GB', infoHash: hash, trackers: [tracker]));
    expect(isMagnet(m), isTrue);
    final q = Uri.parse(m).queryParametersAll;
    expect(q['tr'], [tracker]);
    expect(q['dn'], ['The Kid (1921)']);
    expect(Uri.parse(magnetFor(stream(infoHash: hash, filename: 'a b.mkv', name: 'x'))).queryParameters['dn'],
        'a b.mkv');
  });

  test('a stream without trackers (Torrentio) still gets public trackers', () {
    final q = Uri.parse(magnetFor(stream(infoHash: hash, name: 'Torrentio\n1080p'))).queryParametersAll;
    expect(q['tr'], fallbackTrackers);
  });

  test('describe parses a Torrentio row', () {
    final i = describe(stream(
      name: 'Torrentio\n720p',
      title: 'Rick.and.Morty.S04E02.720p.WEBRip.x264-TBS\n👤 96 💾 307 MB ⚙️ TorrentGalaxy',
    ));
    expect(i.quality, '720p');
    expect(i.seeders, 96);
    expect(i.size, '307 MB');
    expect(i.origin, 'TorrentGalaxy');
    expect(i.lines.first, 'Rick.and.Morty.S04E02.720p.WEBRip.x264-TBS');
    expect(i.lines.join(), isNot(contains('💾')));
  });

  test('describe: Public Domain Movies shape, 4K and unknown quality', () {
    final pdm = describe(stream(name: '1080p', title: '💾 859.37 MB'));
    expect(pdm.quality, '1080p');
    expect(pdm.seeders, isNull);
    expect(pdm.size, '859.37 MB');
    expect(describe(stream(name: 'x', title: 'Movie 2160p')).quality, '4K');
    expect(describe(stream(name: 'x', title: 'Movie.4K.HDR')).quality, '4K');
    expect(describe(stream(name: 'x', title: 'Movie 1.4 GB')).quality, 'Unknown');
    expect(describe(stream(name: 'x', title: 'Movie 1.4 GB')).size, '1.4 GB');
    expect(describe(stream(name: 'x', title: '👤 0')).seeders, 0);
  });

  group('add', () {
    test('normalises stremio://, base and manifest URLs', () async {
      final seen = <String>[];
      final a = await loaded((r) async {
        seen.add('${r.url}');
        return json(manifest(r.url.host));
      });
      final x = await a.add('stremio://one.example/cfg/manifest.json');
      final y = await a.add('https://two.example/cfg/');
      final z = await a.add(' https://three.example/manifest.json ');
      expect(seen, [
        'https://one.example/cfg/manifest.json',
        'https://two.example/cfg/manifest.json',
        'https://three.example/manifest.json',
      ]);
      expect([x.base, y.base, z.base], ['https://one.example/cfg', 'https://two.example/cfg', 'https://three.example']);
      expect(a.all.skip(6), [x, y, z]);
    });

    Future<AddonError?> kind(Future<http.Response> Function(http.Request) h, String input) async {
      final a = await loaded(h);
      try {
        await a.add(input);
        return null;
      } on AddonException catch (e) {
        return e.kind;
      }
    }

    test('maps each failure to an AddonError', () async {
      Future<http.Response> ok(http.Request r) async => json(manifest('x'));
      expect(await kind(ok, 'not a url'), AddonError.invalid);
      expect(await kind(ok, 'ftp://x.example/manifest.json'), AddonError.invalid);
      expect(await kind((_) async => json({'id': 'x'}), 'https://x.example'), AddonError.invalid);
      expect(await kind((_) async => http.Response('<html>', 200), 'https://x.example'), AddonError.invalid);
      expect(await kind((_) async => throw http.ClientException('down'), 'https://x.example'),
          AddonError.unreachable);
      expect(await kind((_) async => json({}, 404), 'https://x.example'), AddonError.server);
      expect(await kind(ok, 'https://v3-cinemeta.strem.io/manifest.json'), AddonError.duplicate);
      expect(await kind((_) async => json(manifest('com.linvo.cinemeta')), 'https://other.example'),
          AddonError.duplicate);
    });
  });

  test('serves honours object resources and idPrefixes', () {
    final a = Addon({
      'id': 'x',
      'name': 'X',
      'resources': [
        'catalog',
        {'name': 'meta', 'types': ['series'], 'idPrefixes': ['kitsu:']},
        {'name': 'stream', 'types': ['movie']},
      ],
      'types': ['movie', 'series'],
      'idPrefixes': ['tt'],
    }, 'https://x');
    expect(a.serves('meta', 'series', 'kitsu:1'), isTrue);
    expect(a.serves('meta', 'series', 'tt1'), isFalse);
    expect(a.serves('meta', 'movie', 'kitsu:1'), isFalse);
    expect(a.serves('stream', 'movie', 'tt1'), isTrue); // falls back to top-level idPrefixes
    expect(a.serves('stream', 'movie', 'kitsu:1'), isFalse);
    expect(a.serves('catalog', 'series', 'tt1'), isTrue);
    expect(a.serves('subtitles', 'movie', 'tt1'), isFalse);
    final any = Addon({'id': 'y', 'name': 'Y', 'resources': ['stream'], 'types': ['movie']}, 'https://y');
    expect(any.serves('stream', 'movie', 'whatever'), isTrue);
  });

  test('catalogs skip required extras and flag search', () {
    final a = Addon({
      'id': 'x',
      'name': 'X',
      'resources': ['catalog'],
      'types': ['movie', 'series', 'anime'],
      'catalogs': [
        {'type': 'movie', 'id': 'top', 'name': 'Top', 'extra': [{'name': 'search'}, {'name': 'skip'}]},
        {'type': 'series', 'id': 'new', 'extra': [{'name': 'genre', 'isRequired': true}]},
        {'type': 'series', 'id': 'old', 'extraRequired': ['genre']},
        {'type': 'channel', 'id': 'yt'},
        {'type': 'series', 'id': 'plain'},
        {'type': 'anime', 'id': 'anime', 'name': 'Anime'},
        {'type': 'anime', 'id': 'search-only', 'extra': [{'name': 'search', 'isRequired': true}]},
      ],
    }, 'https://x');
    expect([for (final c in a.catalogs) '${c.type}/${c.id}/${c.name}/${c.searchable}'],
        ['movie/top/Top/true', 'series/plain/X/false', 'anime/anime/Anime/false']);
  });

  test('catalog builds search and skip URLs and parses metas', () async {
    final seen = <String>[];
    final a = await loaded((r) async {
      seen.add('${r.url}');
      return json({
        'metas': [
          {'id': 'tt1', 'type': 'movie', 'name': 'One', 'poster': 'p', 'releaseInfo': 1999},
          {'name': 'no id'},
        ]
      });
    });
    final c = a.catalogs.firstWhere((c) => c.addon.id == 'com.linvo.cinemeta' && c.type == 'movie');
    final metas = await a.catalog(c, search: 'rick & morty');
    await a.catalog(c, skip: 100);
    await a.catalog(c);
    expect(seen, [
      'https://v3-cinemeta.strem.io/catalog/movie/top/search=rick%20%26%20morty.json',
      'https://v3-cinemeta.strem.io/catalog/movie/top/skip=100.json',
      'https://v3-cinemeta.strem.io/catalog/movie/top.json',
    ]);
    expect(metas.single, (id: 'tt1', type: 'movie', name: 'One', poster: 'p', releaseInfo: '1999'));
  });

  test('bundled catalogs exclude Cinemeta and Kitsu required-extra rows', () async {
    final a = await loaded((_) async => json({}));
    expect([for (final c in a.catalogs) '${c.addon.name}:${c.type}/${c.id}'], [
      'Cinemeta:movie/top',
      'Cinemeta:series/top',
      'Cinemeta:movie/imdbRating',
      'Cinemeta:series/imdbRating',
      'Public Domain Movies:movie/publicdomainmovies',
      'Anime Kitsu:anime/kitsu-anime-trending',
      'Anime Kitsu:anime/kitsu-anime-airing',
      'Anime Kitsu:anime/kitsu-anime-popular',
      'Anime Kitsu:anime/kitsu-anime-rating',
      'Anime Kitsu:series/kitsu-anime-last-videos',
    ]);
    expect([for (final c in a.animeCatalogs) c.name], ['Trending', 'Airing', 'Popular', 'Top rated']);
    expect(a.animeCatalogs.every((c) => c.type == 'anime'), isTrue);
    expect(a.catalogs.where((c) => c.type == 'movie' || c.type == 'series'),
        isNot(contains(anyOf(a.animeCatalogs))));
  });

  test('Anime Kitsu is bundled, on by default and switchable with persistence', () async {
    final a = await loaded((_) async => json({}));
    final kitsu = a.all.singleWhere((b) => b.name == 'Anime Kitsu');
    expect(kitsu.base, 'https://anime-kitsu.strem.fun');
    expect(kitsu.bundled, isTrue);
    expect(kitsu.locked, isFalse);
    expect(a.isEnabled(kitsu), isTrue);
    for (final prefix in ['kitsu', 'mal', 'anilist', 'anidb']) {
      expect(kitsu.serves('meta', 'series', '$prefix:11'), isTrue);
      expect(kitsu.serves('subtitles', 'movie', '$prefix:11'), isTrue);
    }
    expect(kitsu.serves('stream', 'series', 'kitsu:11:1'), isFalse);

    await a.setEnabled(kitsu, false);
    expect(a.animeCatalogs, isEmpty);
    expect(a.active, isNot(contains(kitsu)));
    expect(a.catalogs.any((c) => c.addon == kitsu), isFalse);
    final again = Addons(client: MockClient((_) async => throw StateError('no network on load')));
    await again.load();
    final restored = again.all.singleWhere((b) => b.id == kitsu.id);
    expect(again.isEnabled(restored), isFalse);
    expect(again.animeCatalogs, isEmpty);
    await again.setEnabled(restored, true);
    expect(again.animeCatalogs, hasLength(4));
  });

  test('anime catalog keeps each item type and maps leftover anime to series', () async {
    final seen = <String>[];
    final a = await loaded((r) async {
      seen.add('${r.url}');
      return json({
        'metas': [
          {'id': 'kitsu:11', 'type': 'series', 'name': 'Series'},
          {'id': 'kitsu:12', 'type': 'movie', 'name': 'Movie'},
          {'id': 'kitsu:13', 'type': 'anime', 'name': 'Anime'},
          {'id': 'kitsu:14', 'name': 'Fallback'},
        ],
      });
    });
    final c = a.animeCatalogs.first;
    final items = await a.catalog(c);
    expect(c.type, 'anime');
    expect([for (final item in items) item.type], ['series', 'movie', 'series', 'series']);
    expect(seen.single, 'https://anime-kitsu.strem.fun/catalog/anime/kitsu-anime-trending.json');
  });

  test('Kitsu meta and Torrentio streams use series and canonical episode ids', () async {
    final seen = <String>[];
    final a = await loaded((r) async {
      seen.add('${r.url}');
      if (r.url.path.contains('/meta/')) {
        return json({
          'meta': {
            'id': 'kitsu:11',
            'type': 'anime',
            'name': 'Anime',
            'videos': [
              {'id': 'kitsu:11:1', 'title': 'Episode 1', 'season': 1, 'episode': 1},
            ],
          },
        });
      }
      return json({'streams': [{'name': 'Torrentio', 'infoHash': hash}]});
    });
    final m = await a.meta('anime', 'kitsu:11');
    expect(m.type, 'series');
    expect(m.videos.single.id, 'kitsu:11:1');
    expect(seen.single, 'https://anime-kitsu.strem.fun/meta/series/kitsu:11.json');

    final sources = a.streamSources(m.type, m.videos.single.id);
    expect([for (final source in sources) source.name], ['Torrentio']);
    final torrentio = sources.single;
    expect(torrentio.serves('stream', 'movie', 'tt1'), isTrue);
    expect(torrentio.serves('stream', 'anime', 'kitsu:11:1'), isTrue);
    expect(torrentio.serves('stream', 'series', 'mal:11:1'), isFalse);
    final streams = await a.streams(torrentio, m.type, m.videos.single.id);
    expect(streams.single.infoHash, hash);
    expect(seen.last, 'https://torrentio.strem.fun/stream/series/kitsu:11:1.json');
  });

  test('meta and streams parse real-shaped responses', () async {
    final seen = <String>[];
    final a = await loaded((r) async {
      seen.add('${r.url}');
      if (r.url.path.contains('/meta/')) {
        return json({
          'meta': {
            'id': 'tt0096697',
            'type': 'series',
            'name': 'The Simpsons',
            'genres': ['Animation'],
            'imdbRating': '8.7',
            'videos': [
              {'id': 'tt0096697:1:1', 'name': 'Pilot', 'season': 1, 'episode': 1, 'released': '1989-12-17T00:00:00.000Z'},
            ],
          }
        });
      }
      return json({
        'streams': [
          {
            'name': '1080p',
            'title': 'x\n💾 1 GB',
            'infoHash': hash.toLowerCase(),
            'fileIdx': 0,
            'sources': ['tracker:$tracker', 'dht:${hash.toLowerCase()}'],
            'behaviorHints': {
              'filename': 'x.mkv',
              'videoSize': 1073741824,
              'videoHash': 'abc123',
              'bingeGroup': 'torrentio|1080p|WEB',
              'proxyHeaders': {
                'request': {'User-Agent': 'Flick', 'Bad': 1},
              },
            },
            'subtitles': [
              {'id': 's1', 'url': 'https://s/1.srt', 'lang': 'eng'},
            ],
          },
          {'name': 'yt', 'ytId': 'abc'},
          {'name': 'odd', 'url': 'https://x/a.mkv', 'behaviorHints': {'bingeGroup': 7}},
          {'name': 'Netflix', 'externalUrl': 'https://netflix.com/title/1'},
        ]
      });
    });
    final m = await a.meta('series', 'tt0096697:1:1');
    expect(m.name, 'The Simpsons');
    expect(m.videos.single.season, 1);
    expect(m.videos.single.released, DateTime.utc(1989, 12, 17));
    expect(seen.single, 'https://v3-cinemeta.strem.io/meta/series/tt0096697:1:1.json');

    final src = a.streamSources('series', 'tt0096697:1:1');
    expect([for (final s in src) s.name], ['WatchHub', 'Torrentio']); // PDM is movie-only
    final ss = await a.streams(src.first, 'series', 'tt0096697:1:1');
    expect(seen.last, 'https://watchhub.strem.io/stream/series/tt0096697:1:1.json');
    expect(ss.length, 3);
    expect(ss.first.trackers, [tracker]);
    expect(ss.first.title, 'x\n💾 1 GB');
    expect(ss.first.filename, 'x.mkv');
    expect(ss.first.fileIdx, 0);
    expect(ss.first.headers, {'User-Agent': 'Flick'}); // non-string values dropped
    expect(ss.first.subtitles, [(id: 's1', url: 'https://s/1.srt', lang: 'eng')]);
    expect(ss.first.videoSize, 1073741824);
    expect(ss.first.videoHash, 'abc123');
    expect(ss.first.bingeGroup, 'torrentio|1080p|WEB');
    expect(ss[1].bingeGroup, isNull, reason: 'non-string bingeGroup ignored');
    expect(ss.last.bingeGroup, isNull);
    expect(ss.last.headers, isEmpty);
    expect(ss.last.externalUrl, 'https://netflix.com/title/1');
  });

  test('subtitles merge across addons and ignore failures', () async {
    final a = await loaded((r) async {
      if (r.url.host == 'subs.example') {
        if (r.url.path.endsWith('manifest.json')) return json(manifest('subs', resources: ['subtitles']));
        return json({}, 500);
      }
      return json({
        'subtitles': [
          {'id': '1', 'url': 'https://s/1.srt', 'lang': 'eng'},
        ]
      });
    });
    await a.add('https://subs.example');
    expect(await a.subtitles('movie', 'tt1'), [(id: '1', url: 'https://s/1.srt', lang: 'eng')]);
  });

  test('subtitles send the file hash, size and name as the Stremio extra', () async {
    final seen = <String>[];
    final a = await loaded((r) async {
      seen.add('${r.url}');
      if (r.url.path.endsWith('manifest.json')) return json(manifest('subs', resources: ['subtitles']));
      return json({'subtitles': []});
    });
    await a.add('https://subs.example');
    await a.subtitles('series', 'tt1:4:2', hash: 'ab12', size: 300, filename: 'S04E02 x.mkv');
    expect(seen, contains('https://subs.example/subtitles/series/tt1:4:2/videoHash=ab12&videoSize=300&filename=S04E02%20x.mkv.json'));
  });

  test('persistence round trip, remove then restore keeps position', () async {
    var notified = 0;
    final a = await loaded((r) async => json(manifest(r.url.host)));
    a.addListener(() => notified++);
    final x = await a.add('https://x.example');
    await a.add('https://y.example');
    final pdm = a.all.firstWhere((b) => b.name == 'Public Domain Movies');
    await a.setEnabled(pdm, false);
    await a.setEnabled(a.all.first, false); // Cinemeta is locked
    expect(a.isEnabled(pdm), isFalse);
    expect(a.active.contains(pdm), isFalse);

    final again = Addons(client: MockClient((_) async => throw StateError('no network on load')));
    await again.load();
    expect([for (final b in again.all) b.id].skip(6), ['x.example', 'y.example']);
    expect(again.all.skip(6).first.base, 'https://x.example');
    expect(again.isEnabled(again.all[1]), isFalse);
    expect(again.isEnabled(again.all.first), isTrue);

    await a.remove(x);
    expect([for (final b in a.all.skip(6)) b.id], ['y.example']);
    await a.restore(x);
    expect([for (final b in a.all.skip(6)) b.id], ['x.example', 'y.example']);
    expect(notified, 5);
  });

  test('corrupt prefs fall back to defaults', () async {
    for (final prefs in <Map<String, Object>>[
      {'addons': '{not json', 'addonsDisabled': ['org.stremio.watchhub']},
      {'addons': jsonEncode({'url': 1}), 'addonsDisabled': 'oops'},
      {'addons': 42},
      {'addons': jsonEncode([{'url': 'https://a', 'manifest': {'id': 'a'}}, 'junk'])},
    ]) {
      final a = await loaded((_) async => json({}), prefs);
      expect(a.all.length, 6);
      expect(a.all.every((b) => b.bundled), isTrue);
    }
  });

  test('Torrentio is built in and on, and a copy added by link before is dropped', () async {
    final a = await loaded((_) async => json({}), {
      'addons': jsonEncode([
        {
          'url': 'https://torrentio.strem.fun/manifest.json',
          'manifest': {'id': 'com.stremio.torrentio.addon', 'name': 'Torrentio', 'resources': ['stream']},
        },
      ]),
    });
    final torrentio = a.all.where((b) => b.id == 'com.stremio.torrentio.addon').toList();
    expect(torrentio, hasLength(1));
    expect(torrentio.single.bundled, isTrue);
    expect(a.isEnabled(torrentio.single), isTrue);
    expect([for (final s in a.streamSources('movie', 'tt0012349')) s.name], contains('Torrentio'));
  });
}
