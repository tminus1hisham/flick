import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'addons.dart';

enum AnimeError { blocked, unreachable, changed, unavailable, cancelled }

class AnimeException implements Exception {
  const AnimeException(this.kind);
  final AnimeError kind;
  @override
  String toString() => switch (kind) {
    AnimeError.blocked => 'Miruro is blocking this connection.',
    AnimeError.unreachable => 'The anime source could not be reached.',
    AnimeError.changed => 'The anime source changed how it answers.',
    AnimeError.unavailable => 'This episode or source is unavailable.',
    AnimeError.cancelled => 'Request cancelled.',
  };
}

typedef AnimeCard = ({int id, String title, String? poster});
typedef AnimeEpisode = ({int animeId, String id, int number, String title});

enum AnimeLinkKind { hls, file, page }

typedef AnimeLink = ({
  String url,
  String? quality,
  String server,
  AnimeLinkKind kind,
  Map<String, String> headers,
});
typedef AnimeVariant = ({
  String provider,
  String language,
  List<AnimeLink> streams,
  List<AnimeLink> downloads,
  List<Subtitle> subtitles,
});
typedef AnimeResolution = ({AnimeEpisode episode, List<AnimeVariant> variants});

const miruroOrigins = [
  'https://www.miruro.to',
  'https://www.miruro.ru',
  'https://www.miruro.bz',
  'https://www.miruro.tv',
];
const _maxBody = 2 * 1024 * 1024;

Future<Map<String, dynamic>> decodeAnimeBody(http.Response response) async {
  try {
    if (response.bodyBytes.length > _maxBody) throw const FormatException();
    List<int> bytes = response.bodyBytes;
    if ((response.headers['content-type'] ?? '').split(';').first ==
        'application/octet-stream') {
      // Current public frontend: XOR with "miruro/catalog", then gzip. This is transport obfuscation, not DRM.
      final key = utf8.encode('miruro/catalog');
      bytes = [
        for (var i = 0; i < bytes.length; i++) bytes[i] ^ key[i % key.length],
      ];
      final decoded = <int>[];
      await for (final chunk in gzip.decoder.bind(Stream.value(bytes))) {
        if (decoded.length + chunk.length > 4 * _maxBody) {
          throw const FormatException();
        }
        decoded.addAll(chunk);
      }
      bytes = decoded;
    }
    final body = jsonDecode(utf8.decode(bytes));
    if (body is! Map<String, dynamic>) throw const FormatException();
    return body;
  } catch (_) {
    throw const AnimeException(AnimeError.changed);
  }
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
String? _url(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  return uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty
      ? value
      : null;
}

List<AnimeEpisode> parseAnimeEpisodes(
  int animeId,
  String catalogId,
  Map<String, dynamic> body,
) {
  final entries = body['data'];
  if (entries is! List) throw const AnimeException(AnimeError.changed);
  return [
    for (final e in entries)
      if (e is Map &&
          e['episode_number'] is int &&
          (e['episode_number'] as int) > 0)
        (
          animeId: animeId,
          id: catalogId,
          number: e['episode_number'] as int,
          title: _text(e['title']) ?? 'Episode ${e['episode_number']}',
        ),
  ];
}

Map<String, String> _mediaHeaders(Object? raw) => raw is Map
    ? {
        for (final e in raw.entries)
          if (e.key is String &&
              e.value is String &&
              [
                'referer',
                'origin',
                'user-agent',
                'accept',
                'accept-language',
              ].contains((e.key as String).toLowerCase()) &&
              !(e.value as String).contains(RegExp(r'[\r\n]')))
            (e.key as String).toLowerCase(): e.value as String,
      }
    : {};

AnimeLink? _link(
  Object? value, {
  Map<String, String> headers = const {},
  String server = '',
  bool download = false,
}) {
  if (value is! Map) return null;
  final url = _url(value['url']);
  if (url == null) return null;
  final path = Uri.parse(url).path.toLowerCase();
  final format = value['format'];
  final kind = format == 'hls' || path.endsWith('.m3u8')
      ? AnimeLinkKind.hls
      : ['mp4', 'mkv', 'webm'].contains(format) ||
            RegExp(r'\.(mp4|mkv|webm)$').hasMatch(path)
      ? AnimeLinkKind.file
      : download
      ? AnimeLinkKind.page
      : null;
  if (kind == null) return null;
  return (
    url: url,
    quality: _text(value['quality']),
    server: server,
    kind: kind,
    headers: {...headers, ..._mediaHeaders(value['headers'])},
  );
}

AnimeResolution parseAnimeResolution(
  AnimeEpisode episode,
  Map<String, dynamic> body,
) {
  if (body['tracks'] is! List) throw const AnimeException(AnimeError.changed);
  final variants = <AnimeVariant>[];
  for (final track in body['tracks'] as List) {
    if (track is! Map ||
        !['sub', 'ssub', 'dub'].contains(track['track']) ||
        track['providers'] is! List) {
      continue;
    }
    for (final p in track['providers'] as List) {
      if (p is! Map || _text(p['provider']) == null || p['servers'] is! List) {
        continue;
      }
      final streams = <AnimeLink>[];
      for (final server in p['servers'] as List) {
        if (server is! Map ||
            server['streams'] is! List ||
            server['server'] is! String) {
          continue;
        }
        for (final value in server['streams'] as List) {
          final link = _link(
            value,
            headers: _mediaHeaders(server['headers']),
            server: server['server'] as String,
          );
          if (link != null) streams.add(link);
        }
      }
      final downloads = [
        for (final value
            in p['downloads'] is List ? p['downloads'] as List : const [])
          if (_link(value, download: true) case final AnimeLink link) link,
      ];
      final subtitles = <Subtitle>[
        for (final s
            in p['subtitles'] is List ? p['subtitles'] as List : const [])
          if (s is Map && _url(s['url'] ?? s['file']) != null)
            (
              id: _text(s['id']) ?? (s['url'] ?? s['file']) as String,
              url: (s['url'] ?? s['file']) as String,
              lang: _text(s['language']) ?? _text(s['label']) ?? '',
            ),
      ];
      variants.add((
        provider: p['provider'] as String,
        language: track['track'] as String,
        streams: streams,
        downloads: downloads,
        subtitles: subtitles,
      ));
    }
  }
  return (episode: episode, variants: variants);
}

AddonStream animeStream(AnimeVariant variant, AnimeLink link) => (
  name: variant.provider,
  title: link.quality,
  infoHash: null,
  fileIdx: null,
  url: link.url,
  externalUrl: null,
  trackers: const [],
  filename: null,
  headers: link.headers,
  subtitles: variant.subtitles,
  videoSize: null,
  videoHash: null,
  bingeGroup: null,
);

/// AniList supplies search metadata; Miruro identities are matched by exact external ID.
class Anime {
  Anime({
    http.Client? client,
    this.browser,
    this.origin = 'https://www.miruro.to',
  }) : _http = client ?? http.Client() {
    if (!miruroOrigins.contains(origin)) {
      throw ArgumentError.value(origin, 'origin');
    }
  }
  final http.Client _http;
  final Future<http.Response> Function(Uri)? browser;
  final String origin;
  final _names = <int, String>{};
  bool _closed = false;
  bool _preferBrowser = false;
  void close() {
    _closed = true;
    _http.close();
  }

  void _active() {
    if (_closed) throw const AnimeException(AnimeError.cancelled);
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      final r = await _http
          .get(uri, headers: {'Referer': '$origin/'})
          .timeout(const Duration(seconds: 20));
      _active();
      return r;
    } on AnimeException {
      rethrow;
    } catch (_) {
      _active();
      throw const AnimeException(AnimeError.unreachable);
    }
  }

  bool _blocked(http.Response r) =>
      r.statusCode == 403 ||
      r.statusCode == 444 ||
      r.headers['cf-mitigated'] == 'challenge' ||
      ((r.headers['content-type'] ?? '').contains('text/html') &&
          (r.body.contains('cf-chl-') ||
              r.body.toLowerCase().contains('<title>just a moment')));

  Future<Map<String, dynamic>> _catalog(
    String path, [
    Map<String, String>? query,
  ]) async {
    _active();
    final uri = Uri.parse(
      '$origin/api/v1/anime$path',
    ).replace(queryParameters: query);
    var usedBrowser = _preferBrowser && browser != null;
    http.Response r;
    try {
      r = usedBrowser ? await browser!(uri) : await _get(uri);
      if (!usedBrowser && _blocked(r) && browser != null) {
        usedBrowser = true;
        r = await browser!(uri);
      }
    } catch (_) {
      _preferBrowser = false;
      rethrow;
    }
    _active();
    if (_blocked(r)) {
      _preferBrowser = false;
      throw const AnimeException(AnimeError.blocked);
    }
    if (r.statusCode == 404) throw const AnimeException(AnimeError.unavailable);
    if (r.statusCode != 200) throw const AnimeException(AnimeError.unreachable);
    final body = await decodeAnimeBody(r);
    _preferBrowser = usedBrowser;
    _active();
    return body;
  }

  Future<Map<String, dynamic>> _anilist(
    String query,
    Map<String, Object> variables,
  ) async {
    _active();
    http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query, 'variables': variables}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      _active();
      throw const AnimeException(AnimeError.unreachable);
    }
    _active();
    if (response.statusCode != 200) {
      throw const AnimeException(AnimeError.unreachable);
    }
    try {
      return jsonDecode(response.body)['data'] as Map<String, dynamic>;
    } catch (_) {
      throw const AnimeException(AnimeError.changed);
    }
  }

  Future<List<AnimeCard>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final data = await _anilist(
      r'query($search:String!){Page(perPage:20){media(search:$search,type:ANIME,sort:SEARCH_MATCH){id title{romaji english} coverImage{large}}}}',
      {'search': query.trim()},
    );
    try {
      final media = data['Page']['media'] as List;
      return [for (final m in media) _card(m as Map)];
    } catch (_) {
      throw const AnimeException(AnimeError.changed);
    }
  }

  AnimeCard _card(Map m) {
    final id = m['id'] as int;
    final title = (m['title']['english'] ?? m['title']['romaji']) as String;
    _names[id] = (m['title']['romaji'] ?? title) as String;
    return (id: id, title: title, poster: _url(m['coverImage']?['large']));
  }

  Future<List<AnimeEpisode>> episodes(int id) async {
    if (id <= 0) throw ArgumentError.value(id, 'id');
    if (!_names.containsKey(id)) {
      final data = await _anilist(
        r'query($id:Int!){Media(id:$id,type:ANIME){id title{romaji english}}}',
        {'id': id},
      );
      if (data['Media'] == null) {
        throw const AnimeException(AnimeError.unavailable);
      }
      try {
        _card(data['Media'] as Map);
      } catch (_) {
        throw const AnimeException(AnimeError.changed);
      }
    }
    // shortcut: check the first 15 title matches; use identity lookup if exact IDs are missed.
    final catalog = await _catalog('', {'q': _names[id]!, 'limit': '15'});
    if (catalog['data'] is! List) {
      throw const AnimeException(AnimeError.changed);
    }
    final matches = [
      for (final m in catalog['data'] as List)
        if (m is Map &&
            m['external_ids'] is Map &&
            m['external_ids']['anilist'] is List &&
            (m['external_ids']['anilist'] as List).contains('$id') &&
            m['id'] is String)
          m['id'] as String,
    ];
    if (matches.length != 1) throw const AnimeException(AnimeError.unavailable);
    final catalogId = matches.single;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(catalogId)) {
      throw const AnimeException(AnimeError.changed);
    }
    return parseAnimeEpisodes(
      id,
      catalogId,
      await _catalog('/$catalogId/episodes', {'limit': '10000'}),
    );
  }

  Future<AnimeResolution> resolve(AnimeEpisode episode) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(episode.id) ||
        episode.number <= 0) {
      throw const AnimeException(AnimeError.unavailable);
    }
    return parseAnimeResolution(
      episode,
      await _catalog('/${episode.id}/episodes/${episode.number}/play'),
    );
  }
}
