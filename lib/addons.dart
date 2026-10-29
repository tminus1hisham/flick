import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef MetaPreview = ({String id, String type, String name, String? poster, String? releaseInfo});
typedef Video = ({String id, String title, int? season, int? episode, DateTime? released, String? thumbnail});
typedef Meta = ({
  String id,
  String type,
  String name,
  String? poster,
  String? background,
  String? logo,
  String? description,
  String? releaseInfo,
  String? runtime,
  String? imdbRating,
  List<String> genres,
  List<Video> videos,
});
typedef Catalog = ({Addon addon, String type, String id, String name, bool searchable});
typedef AddonStream = ({
  String? name,
  String? title,
  String? infoHash,
  int? fileIdx,
  String? url,
  String? externalUrl,
  List<String> trackers,
  String? filename,
  Map<String, String> headers, // behaviorHints.proxyHeaders.request, sent with a url stream
  List<Subtitle> subtitles,
  int? videoSize,
  String? videoHash,
});
typedef StreamInfo = ({String quality, int? seeders, String? size, String? origin, List<String> lines});
typedef Subtitle = ({String id, String url, String lang});

enum AddonError { invalid, unreachable, duplicate, server }

class AddonException implements Exception {
  AddonException(this.kind);
  final AddonError kind;
  @override
  String toString() => 'AddonException(${kind.name})';
}

/// One addon manifest served from [base] (the manifest URL minus `/manifest.json`).
class Addon {
  Addon(this._m, this.base, {this.bundled = false, this.locked = false});
  final Map<String, dynamic> _m;
  final String base;
  final bool bundled;
  final bool locked;

  String get id => _m['id'] as String;
  String get name => _m['name'] as String;

  List<String>? _list(Object? v) => v is List ? [for (final e in v) '$e'] : null;

  bool serves(String resource, String type, String id) {
    for (final r in _m['resources'] as List) {
      final own = r is Map ? r : null;
      if ((own?['name'] ?? r) != resource) continue;
      final types = _list(own?['types']) ?? _list(_m['types']);
      final prefixes = _list(own?['idPrefixes']) ?? _list(_m['idPrefixes']);
      if (types != null && !types.contains(type)) return false;
      // ponytail: an empty idPrefixes list matches any id (stremio-core matches none); lenient for odd addons.
      return prefixes == null || prefixes.isEmpty || prefixes.any(id.startsWith);
    }
    return false;
  }

  List<Catalog> get catalogs => [
        for (final c in (_m['catalogs'] as List?) ?? const [])
          if (c is Map &&
              c['id'] is String &&
              (c['type'] == 'movie' || c['type'] == 'series') &&
              !((c['extra'] as List?) ?? const []).any((e) => e is Map && e['isRequired'] == true) &&
              (_list(c['extraRequired']) ?? const []).isEmpty)
            (
              addon: this,
              type: c['type'] as String,
              id: c['id'] as String,
              name: c['name'] as String? ?? name,
              searchable: ((c['extra'] as List?) ?? const []).any((e) => e is Map && e['name'] == 'search') ||
                  (_list(c['extraSupported']) ?? const []).contains('search'),
            ),
      ];

  String get capability {
    final names = [for (final r in _m['resources'] as List) r is Map ? r['name'] : r];
    final types = _list(_m['types']) ?? const [];
    final labels = [
      if (names.contains('catalog')) 'Catalogs',
      if (names.contains('meta')) 'Title details',
      if (names.contains('stream')) 'Streams',
      if (names.contains('subtitles')) 'Subtitles',
      if (!names.contains('catalog'))
        types.contains('movie') && types.contains('series')
            ? 'Movies & series'
            : types.length == 1 && types.first == 'movie'
                ? 'Movies'
                : types.length == 1 && types.first == 'series'
                    ? 'Series'
                    : types.join(', '),
    ];
    return labels.where((l) => l.isNotEmpty).join(' · ');
  }
}

bool _validManifest(Object? m) =>
    m is Map && m['id'] is String && m['name'] is String && m['resources'] is List;

String? _str(Object? v) => v is String ? v : v is num ? '$v' : null;
int? _int(Object? v) => v is num ? v.toInt() : null;

// Stremio keeps ':' raw in path segments (series ids are `tt123:1:2`).
String _seg(String s) => Uri.encodeComponent(s).replaceAll('%3A', ':');

const _timeout = Duration(seconds: 15);

class Addons extends ChangeNotifier {
  Addons({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  late SharedPreferences _prefs;

  final List<Addon> _bundled = [
    for (final b in _bundledManifests) Addon(b.manifest, b.base, bundled: true, locked: b.locked),
  ];
  List<Addon> _user = [];
  Set<String> _disabled = {};
  final _removedAt = <Addon, int>{};

  /// Reads persisted addons; no network, so [all] and [active] are right on the first frame.
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final raw = _prefs.getString('addons');
      _user = [
        for (final e in raw == null ? const [] : jsonDecode(raw) as List)
          if (e is Map && e['url'] is String && _validManifest(e['manifest']))
            Addon((e['manifest'] as Map).cast<String, dynamic>(), _baseOf(e['url'] as String)),
      ];
    } catch (_) {
      _user = [];
    }
    try {
      _disabled = {...?_prefs.getStringList('addonsDisabled')};
    } catch (_) {
      _disabled = {};
    }
  }

  Future<void> _save() async {
    await _prefs.setString('addons', jsonEncode([
      for (final a in _user) {'url': '${a.base}/manifest.json', 'manifest': a._m},
    ]));
    await _prefs.setStringList('addonsDisabled', _disabled.toList());
    notifyListeners();
  }

  List<Addon> get all => [..._bundled, ..._user];
  List<Addon> get active => all.where(isEnabled).toList();

  bool isEnabled(Addon a) => a.locked || !_disabled.contains(a.id);

  Future<void> setEnabled(Addon a, bool on) async {
    if (a.locked) return;
    on ? _disabled.remove(a.id) : _disabled.add(a.id);
    await _save();
  }

  static String _baseOf(String url) {
    final s = url.replaceAll(RegExp(r'/+$'), '');
    return s.endsWith('/manifest.json') ? s.substring(0, s.length - '/manifest.json'.length) : s;
  }

  Future<Map<String, dynamic>> _get(String url) async {
    final http.Response r;
    try {
      r = await _http.get(Uri.parse(url)).timeout(_timeout);
    } on TimeoutException {
      throw AddonException(AddonError.unreachable);
    } on http.ClientException {
      throw AddonException(AddonError.unreachable);
    } on IOException {
      throw AddonException(AddonError.unreachable);
    }
    if (r.statusCode != 200) throw AddonException(AddonError.server);
    try {
      return (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      throw AddonException(AddonError.invalid);
    }
  }

  /// Accepts `stremio://host/...`, a base URL or a manifest URL.
  Future<Addon> add(String input) async {
    var s = input.trim();
    if (s.toLowerCase().startsWith('stremio://')) s = 'https://${s.substring('stremio://'.length)}';
    final u = Uri.tryParse(s);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) {
      throw AddonException(AddonError.invalid);
    }
    final base = _baseOf(s);
    if (all.any((a) => a.base == base)) throw AddonException(AddonError.duplicate);
    final m = await _get('$base/manifest.json');
    if (!_validManifest(m)) throw AddonException(AddonError.invalid);
    if (all.any((a) => a.id == m['id'])) throw AddonException(AddonError.duplicate);
    final a = Addon(m, base);
    _user.add(a);
    await _save();
    return a;
  }

  Future<void> remove(Addon a) async {
    final i = _user.indexOf(a);
    if (i < 0) return;
    _removedAt[a] = i;
    _user.removeAt(i);
    await _save();
  }

  /// Undo for [remove]: back at its old position.
  Future<void> restore(Addon a) async {
    final i = _removedAt.remove(a);
    if (i == null || all.any((b) => b.id == a.id)) return;
    _user.insert(i.clamp(0, _user.length), a);
    await _save();
  }

  List<Catalog> get catalogs => [for (final a in active) ...a.catalogs];

  Future<List<MetaPreview>> catalog(Catalog c, {String? search, int skip = 0}) async {
    final extra = [
      if (search != null) 'search=${Uri.encodeComponent(search)}',
      if (skip > 0) 'skip=$skip',
    ].join('&');
    final body = await _get(
        '${c.addon.base}/catalog/${_seg(c.type)}/${_seg(c.id)}${extra.isEmpty ? '' : '/$extra'}.json');
    return [
      for (final m in (body['metas'] as List?) ?? const [])
        if (m is Map && m['id'] is String)
          (
            id: m['id'] as String,
            type: _str(m['type']) ?? c.type,
            name: _str(m['name']) ?? '',
            poster: _str(m['poster']),
            releaseInfo: _str(m['releaseInfo']),
          ),
    ];
  }

  /// From the first active addon serving meta for ([type], [id]); [AddonError.invalid] when none does.
  Future<Meta> meta(String type, String id) async {
    final a = active.where((a) => a.serves('meta', type, id)).firstOrNull;
    if (a == null) throw AddonException(AddonError.invalid);
    final m = (await _get('${a.base}/meta/${_seg(type)}/${_seg(id)}.json'))['meta'];
    if (m is! Map) throw AddonException(AddonError.invalid);
    return (
      id: _str(m['id']) ?? id,
      type: _str(m['type']) ?? type,
      name: _str(m['name']) ?? '',
      poster: _str(m['poster']),
      background: _str(m['background']),
      logo: _str(m['logo']),
      description: _str(m['description']),
      releaseInfo: _str(m['releaseInfo']),
      runtime: _str(m['runtime']),
      imdbRating: _str(m['imdbRating']),
      genres: [for (final g in (m['genres'] ?? m['genre'] ?? const []) as List) '$g'],
      videos: [
        for (final v in (m['videos'] as List?) ?? const [])
          if (v is Map && v['id'] is String)
            (
              id: v['id'] as String,
              title: _str(v['title']) ?? _str(v['name']) ?? '',
              season: _int(v['season']),
              episode: _int(v['episode']),
              released: DateTime.tryParse(_str(v['released']) ?? ''),
              thumbnail: _str(v['thumbnail']),
            ),
      ],
    );
  }

  List<Addon> streamSources(String type, String videoId) =>
      active.where((a) => a.serves('stream', type, videoId)).toList();

  /// Streams Flick can open; `ytId`-only (and other unplayable) entries are dropped.
  Future<List<AddonStream>> streams(Addon a, String type, String videoId) async {
    final body = await _get('${a.base}/stream/${_seg(type)}/${_seg(videoId)}.json');
    return [
      for (final s in (body['streams'] as List?) ?? const [])
        if (s is Map && (s['infoHash'] is String || s['url'] is String || s['externalUrl'] is String))
          (
            name: _str(s['name']),
            title: _str(s['title']) ?? _str(s['description']),
            infoHash: _str(s['infoHash']),
            fileIdx: _int(s['fileIdx']),
            url: _str(s['url']),
            externalUrl: _str(s['externalUrl']),
            trackers: [
              for (final t in (s['sources'] as List?) ?? const [])
                if (t is String && t.startsWith('tracker:')) t.substring('tracker:'.length),
            ],
            filename: _hints(s)['filename'] is String ? _hints(s)['filename'] as String : null,
            headers: switch (_hints(s)['proxyHeaders']) {
              {'request': final Map r} => {
                  for (final e in r.entries)
                    if (e.value is String) '${e.key}': e.value as String,
                },
              _ => const <String, String>{},
            },
            subtitles: _subs(s['subtitles']),
            videoSize: _int(_hints(s)['videoSize']),
            videoHash: _str(_hints(s)['videoHash']),
          ),
    ];
  }

  static Map _hints(Map s) => s['behaviorHints'] is Map ? s['behaviorHints'] as Map : const {};

  static List<Subtitle> _subs(Object? list) => [
        for (final s in list is List ? list : const [])
          if (s is Map && s['url'] is String)
            (id: _str(s['id']) ?? s['url'] as String, url: s['url'] as String, lang: _str(s['lang']) ?? ''),
      ];

  /// Merged over every active subtitles addon; one addon failing is ignored. The file's hash, size and name
  /// go along as Stremio's extra (`/videoHash=…&videoSize=…&filename=….json`) so addons can match the exact file.
  Future<List<Subtitle>> subtitles(String type, String videoId, {String? hash, int? size, String? filename}) async {
    final extra = [
      if (hash != null) 'videoHash=${Uri.encodeComponent(hash)}',
      if (size != null) 'videoSize=$size',
      if (filename != null) 'filename=${Uri.encodeComponent(filename)}',
    ].join('&');
    final path = '${_seg(type)}/${_seg(videoId)}${extra.isEmpty ? '' : '/$extra'}.json';
    final lists = await Future.wait([
      for (final a in active.where((a) => a.serves('subtitles', type, videoId)))
        _get('${a.base}/subtitles/$path').then((body) => _subs(body['subtitles']), onError: (_) => <Subtitle>[]),
    ]);
    return [for (final l in lists) ...l];
  }
}

final _quality = RegExp(r'\b(2160p|4k|1080p|720p|480p|360p)\b', caseSensitive: false);
final _seeders = RegExp(r'👤\s*(\d+)');
final _sizeTagged = RegExp(r'💾\s*(\d+(?:\.\d+)?\s?[KMGT]i?B)', caseSensitive: false);
final _sizeBare = RegExp(r'\b\d+(?:\.\d+)? ?(?:GB|MB)\b');
final _origin = RegExp('⚙️?\\s*([^\\n]+)');
final _emoji = RegExp(
    // ignore: valid_regexps, the lint parses without unicode: true; \p{...} is valid there (pinned by tests).
    r'[\p{Extended_Pictographic}\p{Regional_Indicator}\p{Emoji_Modifier}\u{FE0F}\u{200D}\u{20E3}]',
    unicode: true);

String _noEmoji(String s) => s.replaceAll(_emoji, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();

StreamInfo describe(AddonStream s) {
  final text = [s.name, s.title].whereType<String>().join('\n');
  final q = _quality.firstMatch(text)?.group(1)!.toLowerCase();
  final origin = _origin.firstMatch(text)?.group(1);
  return (
    quality: q == null ? 'Unknown' : (q == '2160p' || q == '4k' ? '4K' : q),
    seeders: int.tryParse(_seeders.firstMatch(text)?.group(1) ?? ''),
    size: _sizeTagged.firstMatch(text)?.group(1) ?? _sizeBare.firstMatch(text)?.group(0),
    origin: origin == null ? null : _noEmoji(origin),
    lines: [
      for (final l in (s.title ?? '').split('\n'))
        if (_noEmoji(l).isNotEmpty) _noEmoji(l),
    ],
  );
}

String magnetFor(AddonStream s) {
  final firstLine = s.title?.split('\n').first.trim();
  final dn = s.filename ?? (firstLine == null || firstLine.isEmpty ? null : firstLine) ?? s.name ?? '';
  return 'magnet:?xt=urn:btih:${s.infoHash!}&dn=${Uri.encodeComponent(dn)}'
      '${s.trackers.map((t) => '&tr=${Uri.encodeComponent(t)}').join()}';
}

/// Opens [url] outside Flick (Android ACTION_VIEW, handled natively on `flick/torrent`).
Future<void> openExternal(String url) =>
    const MethodChannel('flick/torrent').invokeMethod('openExternal', {'url': url});

// Snapshots of the official addons' live manifests (2026-10-29), trimmed to the fields Flick reads.
const _bundledManifests = <({String base, bool locked, Map<String, dynamic> manifest})>[
  (
    base: 'https://v3-cinemeta.strem.io',
    locked: true,
    manifest: {
      'id': 'com.linvo.cinemeta',
      'name': 'Cinemeta',
      'version': '3.0.14',
      'resources': ['catalog', 'meta', 'addon_catalog'],
      'types': ['movie', 'series'],
      'idPrefixes': ['tt'],
      'catalogs': [
        {'type': 'movie', 'id': 'top', 'name': 'Popular', 'extra': [{'name': 'genre'}, {'name': 'search'}, {'name': 'skip'}]},
        {'type': 'series', 'id': 'top', 'name': 'Popular', 'extra': [{'name': 'genre'}, {'name': 'search'}, {'name': 'skip'}]},
        {'type': 'movie', 'id': 'year', 'name': 'New', 'extra': [{'name': 'genre', 'isRequired': true}, {'name': 'skip'}]},
        {'type': 'series', 'id': 'year', 'name': 'New', 'extra': [{'name': 'genre', 'isRequired': true}, {'name': 'skip'}]},
        {'type': 'movie', 'id': 'imdbRating', 'name': 'Featured', 'extra': [{'name': 'genre'}, {'name': 'skip'}]},
        {'type': 'series', 'id': 'imdbRating', 'name': 'Featured', 'extra': [{'name': 'genre'}, {'name': 'skip'}]},
        {'type': 'series', 'id': 'last-videos', 'name': 'Last videos', 'extra': [{'name': 'lastVideosIds', 'isRequired': true}]},
        {'type': 'series', 'id': 'calendar-videos', 'name': 'Calendar videos', 'extra': [{'name': 'calendarVideosIds', 'isRequired': true}]},
      ],
    },
  ),
  (
    base: 'https://caching.stremio.net/publicdomainmovies.now.sh',
    locked: false,
    manifest: {
      'id': 'org.stremio.pubdomainmovies',
      'name': 'Public Domain Movies',
      'version': '1.0.0',
      'resources': ['catalog', 'stream'],
      'types': ['movie'],
      'idPrefixes': ['tt'],
      'catalogs': [
        {'type': 'movie', 'id': 'publicdomainmovies', 'extra': [{'name': 'skip'}, {'name': 'search'}]},
      ],
    },
  ),
  (
    base: 'https://watchhub.strem.io',
    locked: false,
    manifest: {
      'id': 'org.stremio.watchhub',
      'name': 'WatchHub',
      'version': '1.15.0',
      'resources': ['stream'],
      'types': ['movie', 'series'],
      'idPrefixes': ['tt'],
      'catalogs': [],
    },
  ),
  (
    base: 'https://opensubtitles-v3.strem.io',
    locked: false,
    manifest: {
      'id': 'org.stremio.opensubtitlesv3',
      'name': 'OpenSubtitles v3',
      'version': '1.0.0',
      'resources': ['subtitles'],
      'types': ['movie', 'series'],
      'idPrefixes': ['tt'],
      'catalogs': [],
    },
  ),
];
