import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

final _btih = RegExp(r'^urn:btih:([0-9a-f]{40}|[a-z2-7]{32})$', caseSensitive: false);
final _btmh = RegExp(r'^urn:btmh:1220[0-9a-f]{64}$', caseSensitive: false);

/// True when [s] is a magnet link carrying a BitTorrent v1 or v2 info-hash.
bool isMagnet(String s) {
  try {
    final u = Uri.parse(s.trim());
    if (u.scheme != 'magnet') return false;
    final xt = u.queryParametersAll['xt'] ?? const <String>[];
    return xt.any((v) => _btih.hasMatch(v) || _btmh.hasMatch(v));
  } on FormatException {
    return false; // includes bad percent-encoding, which only surfaces when the query is decoded
  }
}

const _videoExtensions = {
  'mp4', 'm4v', 'mkv', 'webm', 'avi', 'mov', 'ts', 'm2ts', 'wmv', 'flv', 'mpg', 'mpeg'
};

/// True when [name] looks like a video the player can stream.
bool isVideo(String name) {
  final dot = name.lastIndexOf('.');
  return dot >= 0 && _videoExtensions.contains(name.substring(dot + 1).toLowerCase());
}

typedef TorrentStatus = ({String name, int peers, int rate, bool hasMetadata, String? error});
typedef TorrentFile = ({int index, String name, int size});

/// The libtorrent4j engine in android/app/src/main/kotlin/dev/local/flick/Torrents.kt.
class TorrentEngine {
  const TorrentEngine._();
  static const _ch = MethodChannel('flick/torrent');

  Future<int> add(String magnet, String dir) async =>
      (await _ch.invokeMethod<int>('add', {'magnet': magnet, 'dir': dir}))!;

  /// Null once the torrent has been removed.
  Future<TorrentStatus?> status(int id) async {
    final m = await _ch.invokeMapMethod<String, Object?>('status', {'id': id});
    return m == null
        ? null
        : (
            name: m['name'] as String,
            peers: m['peers'] as int,
            rate: m['rate'] as int,
            hasMetadata: m['hasMetadata'] as bool,
            error: m['error'] as String?,
          );
  }

  /// Empty until metadata has arrived.
  Future<List<TorrentFile>> files(int id) async => [
        for (final m in (await _ch.invokeListMethod<Map<Object?, Object?>>('files', {'id': id}))!)
          (index: m['index'] as int, name: m['name'] as String, size: m['size'] as int),
      ];

  /// Starts downloading [file] and returns its loopback stream URL.
  Future<String> stream(int id, int file) async =>
      (await _ch.invokeMethod<String>('stream', {'id': id, 'file': file}))!;

  /// Stops serving and downloading; the torrent stays for another pick.
  Future<void> stopStream(int id) => _ch.invokeMethod('stopStream', {'id': id});

  /// Removes the torrent and deletes its data. Unknown ids are ignored.
  Future<void> remove(int id) => _ch.invokeMethod('remove', {'id': id});

  /// Stops playback and keeps the torrent available for 60 seconds.
  Future<void> release(int id) => _ch.invokeMethod('release', {'id': id});

  /// Downloads only [file], fully, and pins the torrent so release and the 60 s timer leave it alone.
  Future<void> download(int id, int file) => _ch.invokeMethod('download', {'id': id, 'file': file});

  /// The pinned file's progress; null once the torrent is gone.
  Future<TorrentProgress?> progress(int id) async {
    final m = await _ch.invokeMapMethod<String, Object?>('progress', {'id': id});
    return m == null
        ? null
        : (
            bytes: m['bytes'] as int,
            total: m['total'] as int,
            rate: m['rate'] as int,
            peers: m['peers'] as int,
            state: m['state'] as String,
            error: m['error'] as String?,
            path: m['path'] as String?,
          );
  }

  Future<void> pause(int id) => _ch.invokeMethod('pause', {'id': id});
  Future<void> resume(int id) => _ch.invokeMethod('resume', {'id': id});

  /// Removes a download and deletes its files.
  Future<void> delete(int id) => _ch.invokeMethod('delete', {'id': id});

  /// Asks for the notification permission (Android 13+); true when granted.
  Future<bool> requestNotifications() async => await _ch.invokeMethod<bool>('requestNotifications') ?? false;
}

/// state is downloading | paused | done | error.
typedef TorrentProgress = ({int bytes, int total, int rate, int peers, String state, String? error, String? path});

/// The lowercase v1 info-hash in [magnet], or null.
String? infoHashOf(String magnet) {
  for (final v in Uri.parse(magnet.trim()).queryParametersAll['xt'] ?? const <String>[]) {
    final m = _btih.firstMatch(v);
    if (m != null) return m[1]!.toLowerCase();
  }
  return null;
}

/// Where a download's data lives: app storage, never the streaming session folders the engine sweeps.
Future<String> downloadDir(String hash) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/downloads/$hash');
  await dir.create(recursive: true);
  return dir.path;
}

Future<Directory> _root() async =>
    Directory('${(await getTemporaryDirectory()).path}/flick-torrents');

/// The torrent engine. Data left behind by a killed process is swept natively, on the first add.
Future<TorrentEngine> torrentEngine() async => const TorrentEngine._();

/// A fresh directory for one torrent session's data.
Future<Directory> torrentDir() async {
  final root = await _root();
  await root.create(recursive: true);
  return root.createTemp('s');
}

/// Which file to play when a stream names none (enginefs guessFileIdx). A valid [fileIdx]-style choice is the
/// caller's; this picks a unique SxxEyy match, else the sole video ([sure] true), else suggests the largest
/// video for the file list ([sure] false). Null index when there is no video.
({int? index, bool sure}) guessFile(List<TorrentFile> files, {int? season, int? episode}) {
  var videos = files.where((f) => isVideo(f.name)).toList();
  if (season != null && episode != null) {
    final pattern = RegExp(r'(?:^|[^0-9])(?:s(\d+)\.?e(\d+)|(\d+)x(\d+))(?![0-9])',
        caseSensitive: false);
    final matches = videos.where((f) => pattern.allMatches(f.name).any((m) =>
        int.parse(m[1] ?? m[3]!) == season && int.parse(m[2] ?? m[4]!) == episode)).toList();
    if (matches.isNotEmpty) videos = matches;
  }
  if (videos.isEmpty) return (index: null, sure: false);
  videos.sort((a, b) => b.size.compareTo(a.size));
  return (index: videos.first.index, sure: videos.length == 1);
}
