import 'dart:io';

import 'package:libtorrent_flutter/libtorrent_flutter.dart';
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

Future<Directory> _root() async =>
    Directory('${(await getTemporaryDirectory()).path}/flick-torrents');

Future<LibtorrentFlutter>? _engine;

/// The torrent engine, started on first use.
Future<LibtorrentFlutter> torrentEngine() => _engine ??= () async {
      try {
        // Nothing can be streaming before the engine exists, so anything here
        // is left over from a killed process.
        final root = await _root();
        if (root.existsSync()) await root.delete(recursive: true);
        await LibtorrentFlutter.init(fetchTrackers: false, defaultSavePath: root.path);
        return LibtorrentFlutter.instance;
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
