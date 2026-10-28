import 'dart:convert';

import 'package:http/http.dart' as http;

const appVersion = '0.1.0';
const ticksPerSecond = 10000000;

Duration ticksToDuration(int ticks) => Duration(microseconds: ticks ~/ 10);
int durationToTicks(Duration d) => d.inMicroseconds * 10;

enum Quality {
  original('Original', null),
  mbps4('4 Mbps', 4000000),
  mbps1_5('1.5 Mbps', 1500000);

  const Quality(this.label, this.bitrate);
  final String label;
  final int? bitrate;
}

class Item {
  Item(this.json);
  final Map<String, dynamic> json;

  String get id => json['Id'] as String;
  String get name => json['Name'] as String? ?? '';
  String get type => json['Type'] as String? ?? '';
  String? get overview => json['Overview'] as String?;
  String? get seriesName => json['SeriesName'] as String?;
  String? get seriesId => json['SeriesId'] as String?;
  int? get year => json['ProductionYear'] as int?;
  int? get season => json['ParentIndexNumber'] as int?;
  int? get episode => json['IndexNumber'] as int?;
  bool get isFolder => json['IsFolder'] as bool? ?? false;
  bool get playable => type == 'Movie' || type == 'Episode' || type == 'Video';
  Duration? get runtime {
    final t = json['RunTimeTicks'] as int?;
    return t == null ? null : ticksToDuration(t);
  }

  Duration get resumePosition =>
      ticksToDuration((json['UserData']?['PlaybackPositionTicks'] as int?) ?? 0);

  String get title => type == 'Episode'
      ? '${seriesName ?? ''} S${season ?? 0}E${episode ?? 0} · $name'
      : name;
}

class JellyfinClient {
  JellyfinClient({
    required String server,
    required this.deviceId,
    this.token,
    this.userId,
    http.Client? client,
  })  : server = server.replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  final String server;
  final String deviceId;
  String? token;
  String? userId;
  final http.Client _http;

  String get authHeader {
    final base = 'MediaBrowser Client="Flick", Device="Android", '
        'DeviceId="$deviceId", Version="$appVersion"';
    return token == null ? base : '$base, Token="$token"';
  }

  Uri _uri(String path, [Map<String, Object?> query = const {}]) {
    final q = <String, String>{
      for (final e in query.entries)
        if (e.value != null) e.key: '${e.value}',
    };
    return Uri.parse('$server$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> get _headers =>
      {'Authorization': authHeader, 'Content-Type': 'application/json'};

  Future<dynamic> _get(String path, [Map<String, Object?> query = const {}]) async {
    final r = await _http.get(_uri(path, query), headers: _headers);
    if (r.statusCode != 200) throw JellyfinException(r.statusCode, path);
    return jsonDecode(r.body);
  }

  Future<dynamic> _post(String path, Object body) async {
    final r = await _http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    if (r.statusCode >= 300) throw JellyfinException(r.statusCode, path);
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  List<Item> _items(dynamic body) => [
        for (final j in (body is List ? body : body['Items'] as List))
          Item(j as Map<String, dynamic>)
      ];

  Future<bool> reachable() async {
    try {
      final r = await _http
          .get(_uri('/System/Info/Public'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> login(String username, String password) async {
    final body = await _post('/Users/AuthenticateByName', {'Username': username, 'Pw': password});
    token = body['AccessToken'] as String;
    userId = body['User']['Id'] as String;
  }

  Future<List<Item>> views() async => _items(await _get('/UserViews', {'userId': userId}));

  Future<List<Item>> resume() async => _items(await _get('/UserItems/Resume', {
        'userId': userId,
        'mediaTypes': 'Video',
        'limit': 20,
      }));

  Future<List<Item>> latest(String parentId) async => _items(await _get('/Items/Latest', {
        'userId': userId,
        'parentId': parentId,
        'limit': 20,
      }));

  Future<List<Item>> items({String? parentId, String? searchTerm, int start = 0, int limit = 60}) async =>
      _items(await _get('/Items', {
        'userId': userId,
        'parentId': parentId,
        'searchTerm': searchTerm,
        'recursive': true,
        'includeItemTypes': searchTerm == null ? 'Movie,Series' : 'Movie,Series,Episode',
        'sortBy': 'SortName',
        'startIndex': start,
        'limit': limit,
        'fields': 'Overview',
      }));

  Future<Item> item(String id) async =>
      Item(await _get('/Items/$id', {'userId': userId}) as Map<String, dynamic>);

  Future<List<Item>> seasons(String seriesId) async =>
      _items(await _get('/Shows/$seriesId/Seasons', {'userId': userId}));

  Future<List<Item>> episodes(String seriesId, String seasonId) async =>
      _items(await _get('/Shows/$seriesId/Episodes', {
        'userId': userId,
        'seasonId': seasonId,
        'fields': 'Overview',
      }));

  String imageUrl(String itemId, {int maxHeight = 450}) =>
      _uri('/Items/$itemId/Images/Primary', {'maxHeight': maxHeight}).toString();

  String backdropUrl(String itemId, {int maxWidth = 1280}) =>
      _uri('/Items/$itemId/Images/Backdrop', {'maxWidth': maxWidth}).toString();

  String playUrl(Item item, Quality q) => q.bitrate == null
      ? _uri('/Videos/${item.id}/stream', {'static': true, 'api_key': token}).toString()
      : _uri('/Videos/${item.id}/master.m3u8', {
          'mediaSourceId': item.id,
          'videoBitRate': q.bitrate,
          'audioBitRate': 128000,
          'api_key': token,
        }).toString();

  String downloadUrl(Item item, Quality q) => q.bitrate == null
      ? _uri('/Items/${item.id}/Download', {'api_key': token}).toString()
      : _uri('/Videos/${item.id}/stream.mp4', {
          'videoBitRate': q.bitrate,
          'audioBitRate': 128000,
          'api_key': token,
        }).toString();

  Future<void> reportStart(String itemId, Duration pos) =>
      _post('/Sessions/Playing', {'ItemId': itemId, 'PositionTicks': durationToTicks(pos)});

  Future<void> reportProgress(String itemId, Duration pos, {bool paused = false}) =>
      _post('/Sessions/Playing/Progress',
          {'ItemId': itemId, 'PositionTicks': durationToTicks(pos), 'IsPaused': paused});

  Future<void> reportStopped(String itemId, Duration pos) =>
      _post('/Sessions/Playing/Stopped', {'ItemId': itemId, 'PositionTicks': durationToTicks(pos)});
}

class JellyfinException implements Exception {
  JellyfinException(this.status, this.path);
  final int status;
  final String path;
  @override
  String toString() => status == 401 ? 'Wrong username or password' : 'Server error $status on $path';
}
