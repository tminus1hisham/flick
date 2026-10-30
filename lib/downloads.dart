import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'jellyfin.dart';
import 'playback.dart';

/// Direct streams keep their playback identity, without online Up Next or request headers.
class StreamDownload {
  const StreamDownload({required this.title, this.poster, required this.playback});
  final String title;
  final String? poster;
  final Playback playback;

  String toMetaData() => jsonEncode({
        'flickDownload': 'stream',
        'title': title,
        'poster': poster,
        'playback': {
          'title': playback.title,
          'subtitle': playback.subtitle,
          'type': playback.type,
          'videoId': playback.videoId,
          'season': playback.season,
          'episode': playback.episode,
        },
      });

  static StreamDownload? fromMetaData(String value) {
    final m = jsonDecode(value) as Map<String, dynamic>;
    if (m['flickDownload'] != 'stream') return null;
    final p = m['playback'] as Map<String, dynamic>;
    return StreamDownload(
      title: m['title'] as String,
      poster: m['poster'] as String?,
      playback: (
        title: p['title'] as String,
        subtitle: p['subtitle'] as String?,
        type: p['type'] as String,
        videoId: p['videoId'] as String,
        season: p['season'] as int?,
        episode: p['episode'] as int?,
        meta: null,
      ),
    );
  }
}

/// Query strings never become part of the filename; URLs without an extension use MP4.
String streamDownloadFilename(String title, String url, {int? season, int? episode}) {
  var name = title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ').trim();
  name = String.fromCharCodes(name.runes.take(160)).replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) name = 'Video';
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)', caseSensitive: false).hasMatch(name)) {
    name = '_$name';
  }
  if (season != null && episode != null) {
    name += ' S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
  }
  final extension = RegExp(r'\.([a-zA-Z0-9]{1,10})$').firstMatch(Uri.tryParse(url)?.path ?? '')?.group(1);
  return '$name.${extension ?? 'mp4'}';
}

/// Offline downloads. Records live in background_downloader's own database;
/// the item JSON rides along in each task's metaData.
class Downloads extends ChangeNotifier {
  final _fd = FileDownloader();
  List<TaskRecord> records = [];
  late Directory _posters;
  // Cancels land asynchronously after delete() and would re-create the record.
  final _deleted = <String>{};

  Future<void> init() async {
    _posters = Directory('${(await getApplicationDocumentsDirectory()).path}/posters');
    await _posters.create(recursive: true);
    _fd.configureNotification(
      running: const TaskNotification('Downloading', '{displayName}'),
      complete: const TaskNotification('Downloaded', '{displayName}'),
      error: const TaskNotification('Download failed', '{displayName}'),
      progressBar: true,
    );
    // Foreground mode lifts Android's 9-minute limit on non-pausable transcodes.
    await _fd.configure(globalConfig: (Config.runInForeground, true));
    // database.updates fires after the record is stored; _fd.updates fires before.
    _fd.database.updates.listen((r) async {
      if (_deleted.contains(r.taskId)) await _fd.database.deleteRecordWithId(r.taskId);
      await refresh();
    });
    await _fd.start();
    await refresh();
  }

  Future<void> refresh() async {
    records = await _fd.database.allRecords();
    records.sort((a, b) => b.task.creationTime.compareTo(a.task.creationTime));
    notifyListeners();
  }

  StreamDownload? streamOf(TaskRecord r) => StreamDownload.fromMetaData(r.task.metaData);

  Item itemOf(TaskRecord r) {
    final stream = streamOf(r);
    return stream == null
        ? Item(jsonDecode(r.task.metaData) as Map<String, dynamic>)
        : Item({'Id': r.taskId, 'Name': stream.title, 'Type': 'Video'});
  }

  File posterOf(String itemId) => File('${_posters.path}/$itemId.jpg');

  TaskRecord? recordFor(String itemId) =>
      records.where((r) => r.task.taskId == itemId).firstOrNull;

  /// Local file path if [itemId] is fully downloaded.
  Future<String?> localPath(String itemId) async {
    final r = recordFor(itemId);
    if (r == null || r.status != TaskStatus.complete) return null;
    final path = await r.task.filePath();
    return File(path).existsSync() ? path : null;
  }

  Future<void> enqueue(JellyfinClient c, Item item, Quality q) async {
    _deleted.remove(item.id);
    await _fd.permissions.request(PermissionType.notifications);
    try {
      final img = await http.get(Uri.parse(c.imageUrl(item.id)));
      if (img.statusCode == 200) await posterOf(item.id).writeAsBytes(img.bodyBytes);
    } catch (_) {} // poster is cosmetic
    await _fd.enqueue(DownloadTask(
      taskId: item.id,
      url: c.downloadUrl(item, q),
      filename: q == Quality.original ? item.id : '${item.id}.mp4',
      directory: 'videos',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
      // Original is a static file with Range support; transcodes cannot resume.
      allowPause: q == Quality.original,
      retries: 5,
      displayName: item.title,
      metaData: jsonEncode(item.json),
    ));
    await refresh();
  }

  Future<void> enqueueStream({
    required String url,
    Map<String, String> headers = const {},
    required String title,
    String? poster,
    required Playback playback,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      throw ArgumentError.value(url, 'url', 'Expected an HTTP stream URL');
    }
    await _fd.permissions.request(PermissionType.notifications);
    final taskId = 'stream-${DateTime.now().microsecondsSinceEpoch}';
    final task = DownloadTask(
      taskId: taskId,
      url: url,
      headers: Map<String, String>.of(headers),
      filename: streamDownloadFilename(title, url, season: playback.season, episode: playback.episode),
      // Different sources can have the same title and filename.
      directory: 'videos/$taskId',
      baseDirectory: BaseDirectory.applicationDocuments,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 5,
      displayName: playback.subtitle == null ? title : '$title · ${playback.subtitle}',
      metaData: StreamDownload(title: title, poster: poster, playback: playback).toMetaData(),
    );
    if (!await _fd.enqueue(task)) throw StateError('Download was not queued');
    await refresh();
    if (poster != null) {
      try {
        // Stream credentials belong to the video host, never the poster host.
        final img = await http.get(Uri.parse(poster)).timeout(const Duration(seconds: 5));
        if (img.statusCode == 200 && !_deleted.contains(taskId)) {
          await posterOf(taskId).writeAsBytes(img.bodyBytes);
          if (_deleted.contains(taskId)) {
            final p = posterOf(taskId);
            if (p.existsSync()) await p.delete();
          } else {
            notifyListeners();
          }
        }
      } catch (_) {} // poster is cosmetic
    }
  }

  Future<void> pause(TaskRecord r) async => _fd.pause(r.task as DownloadTask);
  Future<void> resume(TaskRecord r) async => _fd.resume(r.task as DownloadTask);

  Future<void> delete(TaskRecord r) async {
    _deleted.add(r.taskId);
    await _fd.cancelTaskWithId(r.taskId);
    final f = File(await r.task.filePath());
    if (f.existsSync()) await f.delete();
    final p = posterOf(r.taskId);
    if (p.existsSync()) await p.delete();
    await _fd.database.deleteRecordWithId(r.taskId);
    await refresh();
  }

  Future<int> bytesUsed() async {
    var total = 0;
    for (final r in records) {
      final f = File(await r.task.filePath());
      if (f.existsSync()) total += await f.length();
    }
    return total;
  }
}
