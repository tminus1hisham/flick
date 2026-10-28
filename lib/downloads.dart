import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'jellyfin.dart';

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

  Item itemOf(TaskRecord r) => Item(jsonDecode(r.task.metaData) as Map<String, dynamic>);

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
