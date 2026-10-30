import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

// Ported from Shineii86/MiruroAPI (MIT).
const _cardFields = '''
  id idMal
  title { romaji english native }
  coverImage { large extraLarge }
  bannerImage format status episodes duration averageScore genres season seasonYear
  nextAiringEpisode { episode airingAt }
''';

String seasonFor(DateTime date) =>
    const ['WINTER', 'SPRING', 'SUMMER', 'FALL'][(date.month - 1) ~/ 3];

({int start, int end}) airingWindow(DateTime date) {
  final start = date.isUtc
      ? DateTime.utc(date.year, date.month, date.day)
      : DateTime(date.year, date.month, date.day);
  final end = date.isUtc
      ? DateTime.utc(date.year, date.month, date.day + 1)
      : DateTime(date.year, date.month, date.day + 1);
  return (start: start.millisecondsSinceEpoch ~/ 1000, end: end.millisecondsSinceEpoch ~/ 1000);
}

String? kitsuAnimeId(Map<String, dynamic> body) {
  final mappings = body['data'];
  if (mappings is! List) return null;
  final ids = <String>{};
  for (final mapping in mappings) {
    if (mapping is! Map || mapping['type'] != 'mappings') continue;
    final attributes = mapping['attributes'];
    if (attributes is! Map ||
        attributes['externalSite'] != 'anilist/anime' ||
        '${attributes['externalId']}' != '20') {
      continue;
    }
    final relationships = mapping['relationships'];
    if (relationships is! Map) continue;
    final item = relationships['item'];
    if (item is! Map) continue;
    final data = item['data'];
    if (data is! Map || data['type'] != 'anime') continue;
    final id = data['id'];
    if (id is String && RegExp(r'^[1-9][0-9]*$').hasMatch(id)) ids.add(id);
  }
  return ids.length == 1 ? ids.single : null;
}

Future<Map<String, dynamic>> _json(Future<http.Response> request) async {
  final response = await request.timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) {
    throw HttpException('HTTP ${response.statusCode}');
  }
  final body = jsonDecode(utf8.decode(response.bodyBytes));
  if (body is! Map<String, dynamic>) throw const FormatException('Expected a JSON object');
  return body;
}

Future<Map<String, dynamic>> _query(
    http.Client client, String query, Map<String, Object> variables) =>
    _json(client.post(
      Uri.parse('https://graphql.anilist.co'),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, 'variables': variables}),
    ));

Map _data(Map<String, dynamic> body) {
  final errors = body['errors'];
  if (errors != null && (errors is! List || errors.isNotEmpty)) {
    throw FormatException('GraphQL errors: ${jsonEncode(errors)}');
  }
  final data = body['data'];
  if (data is! Map) throw const FormatException('Missing GraphQL data');
  return data;
}

Future<bool> _check(String label, String filename,
    Future<Map<String, dynamic>> Function() fetch, void Function(Map<String, dynamic>) validate) async {
  final file = File('test/fixtures/anime/$filename');
  try {
    if (await file.exists()) await file.delete();
    final body = await fetch();
    await file.parent.create(recursive: true);
    await file.writeAsString('${const JsonEncoder.withIndent('  ').convert(body)}\n');
    validate(body);
    stdout.writeln('ok $label -> ${file.path}');
    return true;
  } catch (error) {
    stdout.writeln('FAIL $label: ${error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ')}');
    return false;
  }
}

Future<void> main() async {
  final client = http.Client();
  final now = DateTime.now();
  final day = airingWindow(now);
  String? kitsuId;
  var infoOk = false;
  var mappingOk = false;
  var episodesOk = false;
  try {
    infoOk = await _check('AniList Media 20', 'info_20.json', () => _query(client, '''
      query {
        Media(id: 20, type: ANIME) {
          $_cardFields
          description
          streamingEpisodes { title thumbnail url site }
          externalLinks { site url type }
        }
      }
    ''', {}), (body) {
      final media = _data(body)['Media'];
      if (media is! Map || media['id'] != 20 || media['title'] is! Map ||
          media['streamingEpisodes'] is! List || media['externalLinks'] is! List) {
        throw const FormatException('Missing Media 20 metadata or link lists');
      }
    });

    await _check('AniList season ${seasonFor(now)} ${now.year}', 'season.json',
        () => _query(client, '''
      query (\$season: MediaSeason!, \$year: Int!) {
        Page(perPage: 6) {
          media(season: \$season, seasonYear: \$year, type: ANIME, sort: POPULARITY_DESC) {
            $_cardFields
          }
        }
      }
    ''', {'season': seasonFor(now), 'year': now.year}), (body) {
      final page = _data(body)['Page'];
      if (page is! Map || page['media'] is! List || (page['media'] as List).isEmpty) {
        throw const FormatException('Missing seasonal media');
      }
    });

    await _check('AniList airing today (${now.timeZoneName})', 'airing.json',
        () => _query(client, '''
      query (\$start: Int!, \$end: Int!) {
        Page(perPage: 50) {
          pageInfo { currentPage hasNextPage }
          airingSchedules(airingAt_greater: \$start, airingAt_lesser: \$end, sort: TIME) {
            id episode airingAt
            media { $_cardFields }
          }
        }
      }
    ''', {'start': day.start - 1, 'end': day.end}), (body) {
      final page = _data(body)['Page'];
      if (page is! Map || page['airingSchedules'] is! List) {
        throw const FormatException('Missing airing schedule');
      }
    });

    mappingOk = await _check('Kitsu mapping (unreachable on transport/HTTP failure)',
        'kitsu_mapping_20.json', () => _json(client.get(
          Uri.https('kitsu.io', '/api/edge/mappings', {
            'filter[externalSite]': 'anilist/anime',
            'filter[externalId]': '20',
            'include': 'item',
          }),
          headers: {'Accept': 'application/vnd.api+json'},
        )), (body) {
      kitsuId = kitsuAnimeId(body);
      if (kitsuId == null) {
        throw const FormatException('No unique Kitsu anime id; inspect kitsu_mapping_20.json');
      }
    });
    if (mappingOk) stdout.writeln('Kitsu anime id: $kitsuId');

    episodesOk = await _check('Kitsu episodes (unreachable on transport/HTTP failure)',
        'kitsu_episodes.json', () {
      if (kitsuId == null) throw StateError('Cannot request episodes without a Kitsu anime id');
      return _json(client.get(
        Uri.https('kitsu.io', '/api/edge/anime/$kitsuId/episodes', {'page[limit]': '20'}),
        headers: {'Accept': 'application/vnd.api+json'},
      ));
    }, (body) {
      final episodes = body['data'];
      if (episodes is! List || episodes.isEmpty ||
          episodes.any((e) => e is! Map || e['type'] != 'episodes' || e['attributes'] is! Map)) {
        throw const FormatException('Missing Kitsu episode resources');
      }
    });
  } finally {
    client.close();
  }
  await stdout.flush();
  exit(infoOk && mappingOk && episodesOk && kitsuId != null ? 0 : 1);
}
