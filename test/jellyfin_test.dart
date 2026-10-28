import 'dart:convert';

import 'package:flick/jellyfin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final episodeJson = {
  'Id': 'ep1',
  'Name': 'Pilot',
  'Type': 'Episode',
  'SeriesName': 'Show',
  'SeriesId': 's1',
  'ParentIndexNumber': 1,
  'IndexNumber': 2,
  'RunTimeTicks': 30 * 60 * ticksPerSecond,
  'UserData': {'PlaybackPositionTicks': 90 * ticksPerSecond},
};

void main() {
  test('auth header adds token only after login', () async {
    late http.Request seen;
    final c = JellyfinClient(
      server: 'https://srv/',
      deviceId: 'dev',
      client: MockClient((r) async {
        seen = r;
        return http.Response(jsonEncode({'AccessToken': 'tok', 'User': {'Id': 'u1'}}), 200);
      }),
    );
    expect(c.authHeader, isNot(contains('Token=')));
    await c.login('demo', '');
    expect(seen.url.toString(), 'https://srv/Users/AuthenticateByName');
    expect(jsonDecode(seen.body), {'Username': 'demo', 'Pw': ''});
    expect(c.authHeader, endsWith('Version="$appVersion", Token="tok"'));
    expect(c.userId, 'u1');
  });

  test('ticks convert both ways', () {
    expect(ticksToDuration(15 * ticksPerSecond), const Duration(seconds: 15));
    expect(durationToTicks(const Duration(seconds: 15)), 15 * ticksPerSecond);
  });

  test('item parses real-shaped episode json', () {
    final i = Item(episodeJson);
    expect(i.title, 'Show S1E2 · Pilot');
    expect(i.runtime, const Duration(minutes: 30));
    expect(i.resumePosition, const Duration(seconds: 90));
    expect(i.playable, isTrue);
  });

  test('play and download urls per quality', () {
    final c = JellyfinClient(server: 'https://srv', deviceId: 'd', token: 't');
    final i = Item(episodeJson);
    expect(c.playUrl(i, Quality.original), 'https://srv/Videos/ep1/stream?static=true&api_key=t');
    final hls = Uri.parse(c.playUrl(i, Quality.mbps1_5));
    expect(hls.path, '/Videos/ep1/master.m3u8');
    expect(hls.queryParameters['videoBitRate'], '1500000');
    expect(c.downloadUrl(i, Quality.original), 'https://srv/Items/ep1/Download?api_key=t');
    final mp4 = Uri.parse(c.downloadUrl(i, Quality.mbps4));
    expect(mp4.path, '/Videos/ep1/stream.mp4');
    expect(mp4.queryParameters['videoBitRate'], '4000000');
  });

  test('items query drops null params and parses list', () async {
    late Uri seen;
    final c = JellyfinClient(
      server: 'https://srv',
      deviceId: 'd',
      userId: 'u',
      client: MockClient((r) async {
        seen = r.url;
        return http.Response(jsonEncode({'Items': [episodeJson]}), 200);
      }),
    );
    final items = await c.items(searchTerm: 'pil');
    expect(items.single.id, 'ep1');
    expect(seen.queryParameters.containsKey('parentId'), isFalse);
    expect(seen.queryParameters['includeItemTypes'], 'Movie,Series,Episode');
  });
}
