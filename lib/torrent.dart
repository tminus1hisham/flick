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
}

Future<Directory> _root() async =>
    Directory('${(await getTemporaryDirectory()).path}/flick-torrents');

Future<TorrentEngine>? _engine;

/// The torrent engine. The first call also clears data left behind by a killed process.
Future<TorrentEngine> torrentEngine() => _engine ??= () async {
      try {
        // Nothing can be streaming before the first call, so anything here is a leftover.
        final root = await _root();
        if (root.existsSync()) await root.delete(recursive: true);
        return const TorrentEngine._();
      } catch (_) {
        _engine = null; // let a retry start over
        rethrow;
      }
    }();

/// A fresh directory for one torrent session's data.
Future<Directory> torrentDir() async {
  final root = await _root();
  await root.create(recursive: true);
  return root.createTemp('s');
}
