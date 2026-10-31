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

/// Native persistence owns the data directory; ids are refreshed by resumeKept after a restart.
class KeptTorrent {
  const KeptTorrent({
    required this.id, required this.infoHash, required this.magnet, required this.file,
    required this.dir, required this.titleJson, required this.name, required this.size, required this.done,
  });
  final int id;
  final String infoHash, magnet, dir, titleJson, name;
  final int file, size;
  final bool done;

  String get taskId => 'torrent-$infoHash-$file';

  factory KeptTorrent.fromJson(Map<String, Object?> m) => KeptTorrent(
    id: m['id'] as int,
    infoHash: m['infoHash'] as String,
    magnet: m['magnet'] as String,
    file: m['file'] as int,
    dir: m['dir'] as String,
    titleJson: m['titleJson'] as String,
    name: m['name'] as String,
    size: m['size'] as int,
    done: m['done'] as bool,
  );

  Map<String, Object?> toJson() => {
    'id': id, 'infoHash': infoHash, 'magnet': magnet, 'file': file,
    'dir': dir, 'titleJson': titleJson, 'name': name, 'size': size, 'done': done,
  };
}

/// Progress counts bytes in the selected file, never bytes in the whole season pack.
class TorrentProgress {
  const TorrentProgress({
    required this.downloaded, required this.total, required this.done, this.path, this.error,
  });
  final int downloaded, total;
  final bool done;
  final String? path, error;

  double get progress => total > 0 ? (downloaded / total).clamp(0.0, 1.0).toDouble() : 0;
  bool get active => !done && error == null;

  factory TorrentProgress.fromStatus(Map<String, Object?> m) {
    final total = ((m['total'] as num?)?.toInt() ?? 0).clamp(0, 0x7fffffffffffffff).toInt();
    final bytes = ((m['downloaded'] as num?)?.toInt() ?? 0).clamp(0, 0x7fffffffffffffff).toInt();
    final path = m['path'] as String?;
    final error = m['error'] as String?;
    final done = m['done'] == true && total > 0 && bytes >= total &&
        path != null && path.isNotEmpty && error == null;
    return TorrentProgress(
      downloaded: total > 0 ? bytes.clamp(0, total).toInt() : bytes,
      total: total,
      done: done,
      path: done ? path : null,
      error: error,
    );
  }
}

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

  Future<TorrentProgress?> downloadStatus(int id) async {
    final m = await _ch.invokeMapMethod<String, Object?>('status', {'id': id});
    return m == null ? null : TorrentProgress.fromStatus(m);
  }

  /// Promotes this entry out of the streaming cache and persists its selected file and title.
  Future<KeptTorrent> keep(int id, int file, {required String titleJson}) async {
    final m = await _ch.invokeMapMethod<String, Object?>(
        'keep', {'id': id, 'file': file, 'titleJson': titleJson});
    return KeptTorrent.fromJson(m!);
  }

  /// Idempotent within the native engine; returned ids belong to the current process.
  Future<List<KeptTorrent>> resumeKept() async => [
    for (final m in (await _ch.invokeListMethod<Map<Object?, Object?>>('resumeKept'))!)
      KeptTorrent.fromJson(Map<String, Object?>.from(m)),
  ];

  /// Empty until metadata has arrived.
  Future<List<TorrentFile>> files(int id) async => [
        for (final m in (await _ch.invokeListMethod<Map<Object?, Object?>>('files', {'id': id}))!)
          (index: m['index'] as int, name: m['name'] as String, size: m['size'] as int),
      ];

  /// Starts downloading [file] and returns its loopback stream URL.
  Future<String> stream(int id, int file) async =>
      (await _ch.invokeMethod<String>('stream', {'id': id, 'file': file}))!;

  /// Stops streaming. A kept download continues until its selected file is complete.
  Future<void> stopStream(int id) => _ch.invokeMethod('stopStream', {'id': id});

  /// Removes the torrent and deletes its data. Retries can protect a pre-existing download.
  Future<void> remove(int id, {bool unlessKept = false}) =>
      _ch.invokeMethod('remove', {'id': id, 'unlessKept': unlessKept});

  /// Stops playback; kept downloads survive, other torrents stay available for 60 seconds.
  Future<void> release(int id) => _ch.invokeMethod('release', {'id': id});

  /// The playing file's average bytes per second, which spaces the piece deadlines ahead of the player.
  Future<void> bitrate(int id, int bytesPerSec) =>
      _ch.invokeMethod('bitrate', {'id': id, 'bytesPerSec': bytesPerSec});

  /// Whether this is an Android TV. False when the platform can't tell.
  Future<bool> isTv() async {
    try {
      return await _ch.invokeMethod<bool>('tv') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// A download rate for display, such as "1.8 MB/s".
String formatRate(int bytesPerSec) => '${(bytesPerSec / (1 << 20)).toStringAsFixed(1)} MB/s';

/// Whether the phone has a validated network. True when it can't tell.
Future<bool> networkOnline() async {
  try {
    return await TorrentEngine._ch.invokeMethod<bool>('online') ?? true;
  } catch (_) {
    return true;
  }
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
