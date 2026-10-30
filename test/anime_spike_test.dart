import 'package:flutter_test/flutter_test.dart';

import '../tool/anime_spike.dart';

Map<String, dynamic> mappingBody(List<Object?> mappings) => {'data': mappings};

Map<String, dynamic> mapping({
  String site = 'anilist/anime',
  Object externalId = '20',
  String type = 'anime',
  Object id = '11',
}) => {
  'type': 'mappings',
  'attributes': {'externalSite': site, 'externalId': externalId},
  'relationships': {
    'item': {
      'data': {'type': type, 'id': id},
    },
  },
};

void main() {
  test('season follows the calendar quarter at every month boundary', () {
    const expected = [
      'WINTER', 'WINTER', 'WINTER',
      'SPRING', 'SPRING', 'SPRING',
      'SUMMER', 'SUMMER', 'SUMMER',
      'FALL', 'FALL', 'FALL',
    ];
    for (var month = 1; month <= 12; month++) {
      expect(seasonFor(DateTime(2026, month, 1)), expected[month - 1]);
      expect(seasonFor(DateTime(2026, month + 1, 0)), expected[month - 1]);
    }
  });

  test('airing window covers the local calendar day', () {
    final day = airingWindow(DateTime(2026, 10, 30, 15, 45));
    expect(day.start, DateTime(2026, 10, 30).millisecondsSinceEpoch ~/ 1000);
    expect(day.end, DateTime(2026, 10, 31).millisecondsSinceEpoch ~/ 1000);
  });

  test('airing window handles UTC leap days and year rollover', () {
    for (final date in [DateTime.utc(2024, 2, 29, 23), DateTime.utc(2026, 12, 31, 12)]) {
      final day = airingWindow(date);
      expect(day.start, DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch ~/ 1000);
      expect(day.end, DateTime.utc(date.year, date.month, date.day + 1).millisecondsSinceEpoch ~/ 1000);
      expect(day.end - day.start, 86400);
    }
  });

  test('mapping uses the anime relationship id, never the mapping resource id', () {
    final resource = mapping()..['id'] = '99999';
    expect(kitsuAnimeId(mappingBody([resource])), '11');
    expect(kitsuAnimeId(mappingBody([mapping(externalId: 20)])), '11');
    expect(kitsuAnimeId(mappingBody([mapping(), mapping()])), '11');
  });

  test('mapping ignores unrelated resources and rejects ambiguous matches', () {
    expect(kitsuAnimeId(mappingBody([
      mapping(site: 'myanimelist/anime', id: '1'),
      mapping(externalId: '200', id: '2'),
      mapping(type: 'manga', id: '3'),
      mapping(),
    ])), '11');
    expect(kitsuAnimeId(mappingBody([mapping(), mapping(id: '12')])), isNull);
  });

  test('mapping rejects missing, malformed and nonpositive identifiers', () {
    for (final body in <Map<String, dynamic>>[
      {},
      {'data': null},
      {'data': {}},
      mappingBody([]),
      mappingBody([null, 'invalid', {'type': 'mappings'}]),
      mappingBody([mapping(id: '')]),
      mappingBody([mapping(id: '0')]),
      mappingBody([mapping(id: '-1')]),
      mappingBody([mapping(id: '11x')]),
      mappingBody([mapping(id: 11)]),
      mappingBody([{
        'type': 'mappings',
        'attributes': {'externalSite': 'anilist/anime', 'externalId': '20'},
        'relationships': {'item': {'data': null}},
      }]),
    ]) {
      expect(kitsuAnimeId(body), isNull);
    }
  });
}
