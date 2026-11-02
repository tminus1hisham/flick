import 'package:flutter/services.dart';

typedef LiveEvent = ({int id, int sport, String name, String league, DateTime start, int status});
typedef LiveChannel = ({int id, int sport, int eventId, int site, String name, bool available});
typedef LiveSource = ({String url, Map<String, String> headers});

const liveSports = {
  1: 'Football', 2: 'Basketball', 3: 'Tennis', 4: 'Baseball', 6: 'Cricket',
  7: 'Motorsport', 8: 'Rugby', 9: 'American football', 10: 'Australian football',
  11: 'Hockey', 12: 'Badminton', 13: 'Volleyball', 14: 'Fighting', 15: 'Cycling',
  16: 'Handball', 17: 'Golf', 18: 'Darts', 19: 'Athletics', 90: 'Other',
};

String liveError(Object error) => error is PlatformException
    ? error.message ?? 'This live source is unavailable.'
    : 'Could not load the live source. Try again.';

class LiveClient {
  static const _channel = MethodChannel('flick/live');

  Future<void> stop() => _channel.invokeMethod<void>('stop');

  Future<List<LiveEvent>> events(int sport) async {
    final rows = await _channel.invokeListMethod<dynamic>('events', {'sport': sport}) ?? [];
    return [for (final r in rows) (
      id: r['id'] as int, sport: r['sport'] as int, name: r['name'] as String,
      league: r['league'] as String, start: DateTime.fromMillisecondsSinceEpoch(r['start'] as int).toLocal(),
      status: r['status'] as int,
    )];
  }

  Future<List<LiveChannel>> channels(LiveEvent event) async {
    final rows = await _channel.invokeListMethod<dynamic>('channels', {'sport': event.sport, 'eventId': event.id}) ?? [];
    return [for (final r in rows) (
      id: r['id'] as int, sport: r['sport'] as int, eventId: r['eventId'] as int,
      site: r['site'] as int, name: r['name'] as String, available: r['available'] as bool,
    )];
  }

  Future<LiveSource> resolve(LiveChannel channel) => _source('resolve', channel);
  Future<LiveSource> prepare(LiveChannel channel) => _source('prepare', channel);
  Future<void> commit(LiveSource source) => _channel.invokeMethod<void>('commit', {'url': source.url});
  Future<void> cancelPrepared() => _channel.invokeMethod<void>('cancelPrepared');

  Future<LiveSource> _source(String method, LiveChannel channel) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(method, {
      'sport': channel.sport, 'eventId': channel.eventId, 'id': channel.id, 'site': channel.site,
    });
    if (result == null) throw const FormatException('Missing live source');
    return (url: result['url'] as String, headers: Map<String, String>.from(result['headers'] as Map));
  }
}
