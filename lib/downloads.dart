import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'playback.dart';
import 'addons.dart' show Subtitle;
import 'history.dart';
import 'offline_subtitles.dart';
import 'torrent.dart';

/// Direct streams keep their playback identity, without online Up Next or request headers.
class StreamDownload {
  const StreamDownload({required this.title, this.poster, required this.playback, this.subtitles = const []});
  final List<Subtitle> subtitles;
  final String title;
  final String? poster;
  final Playback playback;

  String toMetaData() => jsonEncode({
        'flickDownload': 'stream',
        'title': title,
        'poster': poster,
        'subtitles': _writeSubtitles(subtitles),
        'playback': {
          'title': playback.title,
          'subtitle': playback.subtitle,
          'logo': playback.logo,
          'poster': playback.poster,
          'type': playback.type,
          'videoId': playback.videoId, 'scope': writeContentScope(playback.scope),
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
      subtitles: _readSubtitles(m['subtitles']),
      playback: (
        title: p['title'] as String,
        subtitle: p['subtitle'] as String?,
        logo: p['logo'] as String?,
        poster: (p['poster'] ?? m['poster']) as String?,
        type: p['type'] as String,
        videoId: p['videoId'] as String,
        season: p['season'] as int?,
        episode: p['episode'] as int?,
        scope: readContentScope(p['scope']), meta: null,
      ),
    );
  }
}

List<Map<String, String>> _writeSubtitles(List<Subtitle> subtitles) => [
  for (final s in subtitles) {'id': s.id, 'url': s.url, 'lang': s.lang},
];
List<Subtitle> _readSubtitles(Object? value) => [
  for (final s in value is List ? value : const [])
    if (s is Map && s['id'] is String && s['url'] is String && s['lang'] is String)
      (id: s['id'] as String, url: s['url'] as String, lang: s['lang'] as String),
];

/// Adapts a native torrent to the same row states as an HTTP download.
class TorrentDownload {
  TorrentDownload(this.kept)
      : stream = StreamDownload.fromMetaData(kept.titleJson)!;
  final KeptTorrent kept;
  final StreamDownload stream;
  TorrentProgress? info;

  String get taskId => kept.taskId;
  bool get active => info?.active ?? true;
  TaskStatus get status => info?.error != null ? TaskStatus.failed
      : info?.done == true ? TaskStatus.complete
      : info == null ? TaskStatus.enqueued : TaskStatus.running;
  double get progress => info?.progress ?? 0;
  int get expectedFileSize => info?.total ?? kept.size;
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

enum DownloadState { queued, downloading, paused, done, failed }

/// The engine's progress state as ours; anything it adds later reads as still downloading.
DownloadState downloadState(String engine) => switch (engine) {
      'paused' => DownloadState.paused,
      'done' => DownloadState.done,
      'error' => DownloadState.failed,
      _ => DownloadState.downloading,
    };

/// One torrent file kept on this phone. bytes, rate, peers and error are live only; the rest is persisted.
class Download {
  Download(
      {required this.hash, required this.magnet, required this.file, required this.playback, this.poster,
      this.path = '', this.state = DownloadState.queued, this.total = 0, this.subtitles = const []});
  final List<Subtitle> subtitles;
  String get taskId => 'legacy-$hash-$file';
  final String hash, magnet;
  final int file;
  final Playback playback;
  final String? poster;
  String path;
  DownloadState state;
  int bytes = 0, total, rate = 0, peers = 0;
  String? error;
  bool waiting = false;

  Map<String, Object?> toJson() => {
        'hash': hash, 'magnet': magnet, 'file': file, 'poster': poster, 'path': path, 'state': state.name,
        'total': total,
        'subtitles': _writeSubtitles(subtitles),
        'playback': {
          'title': playback.title, 'subtitle': playback.subtitle, 'logo': playback.logo, 'poster': playback.poster, 'type': playback.type,
          'videoId': playback.videoId, 'scope': writeContentScope(playback.scope), 'season': playback.season, 'episode': playback.episode,
        },
      };

  factory Download.fromJson(Map<String, Object?> j) {
    final p = j['playback'] as Map<String, Object?>;
    return Download(
      hash: j['hash'] as String,
      magnet: j['magnet'] as String,
      file: j['file'] as int,
      poster: j['poster'] as String?,
      path: j['path'] as String,
      state: DownloadState.values.byName(j['state'] as String),
      total: j['total'] as int,
      subtitles: _readSubtitles(j['subtitles']),
      playback: (
        title: p['title'] as String,
        subtitle: p['subtitle'] as String?,
        logo: p['logo'] as String?,
        poster: (p['poster'] ?? j['poster']) as String?,
        scope: readContentScope(p['scope']), meta: null,
        type: p['type'] as String,
        videoId: p['videoId'] as String,
        season: p['season'] as int?,
        episode: p['episode'] as int?,
      ),
    );
  }
}

/// HTTP records live in background_downloader's database; native torrents persist separately.
// shortcut: legacy kept records coexist with the native registry; consolidate only with a data migration.
class Downloads extends ChangeNotifier {
  /// [engine] and [dirFor] are seams for tests.
  Downloads({TorrentEngine? engine, FileDownloader? downloader, this.dirFor = downloadDir, OfflineSubtitles? subtitles})
      : _engine = engine, _fd = downloader ?? FileDownloader(), subtitles = subtitles ?? OfflineSubtitles();
  final OfflineSubtitles subtitles;
  TorrentEngine? _engine;
  final Future<String> Function(String hash) dirFor;
  late SharedPreferences _prefs;
  List<Download> items = [];

  /// Info-hash → engine id. Ids last one process, so load() adds every unfinished download again.
  final _ids = <String, int>{};
  Timer? _poll;
  bool _polling = false;

  Future<TorrentEngine> get _e async => _engine ??= await torrentEngine();
  static bool _active(Download d) => d.state == DownloadState.queued || d.state == DownloadState.downloading;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    items = [
      for (final j in jsonDecode(_prefs.getString('downloads') ?? '[]') as List)
        Download.fromJson(j as Map<String, Object?>),
    ];
    for (final d in items) {
      // Finished files play from their path with no torrent behind them.
      if (d.state == DownloadState.done) {
        if (!File(d.path).existsSync()) {
          d.state = DownloadState.failed;
          d.error = 'File missing';
        }
        continue;
      }
      try {
        await _register(d);
        if (d.state == DownloadState.paused) {
          await (await _e).pause(_ids[d.hash]!);
        } else {
          d.state = DownloadState.queued;
        }
      } catch (e) {
        d.state = DownloadState.failed;
        d.error = _reason(e);
      }
    }
    _watch();
  }

  /// Adds the torrent (the engine reuses a live one with the same hash) and pins [Download.file].
  Future<void> _register(Download d) async {
    final e = await _e;
    final id = await e.add(d.magnet, await dirFor(d.hash), downloadOnly: true);
    _ids[d.hash] = id;
    await e.download(id, d.file);
  }

  /// Registers [file] of [magnet]. Throws, with nothing listed, when the engine refuses it.
  Future<void> start(String magnet, Playback playback, int file, {String? poster, List<Subtitle> subtitles = const []}) async {
    final hash = infoHashOf(magnet)!;
    final old = of(hash, file);
    if (old != null && old.state != DownloadState.failed) return;
    final d = Download(hash: hash, magnet: magnet, file: file, playback: playback, poster: poster, subtitles: subtitles);
    _deleted.remove(d.taskId);
    await _register(d);
    if (old != null) items.remove(old);
    items.insert(0, d);
    HapticFeedback.lightImpact();
    await _changed();
    if (!(_prefs.getBool('notificationsAsked') ?? false)) {
      await _prefs.setBool('notificationsAsked', true);
      unawaited((await _e).requestNotifications().catchError((Object _) => false));
    }
  }

  Future<void> pauseNative(Download d) async {
    await (await _e).pause(_ids[d.hash]!);
    d.state = DownloadState.paused;
    await _changed();
  }

  /// Resumes a paused download; a failed one (or one the engine lost) is added and pinned again.
  Future<void> resumeNative(Download d) async {
    final id = _ids[d.hash];
    if (d.state == DownloadState.paused && id != null) {
      await (await _e).resume(id);
    } else {
      await _register(d);
    }
    d.state = DownloadState.queued;
    d.error = null;
    await _changed();
  }

  Future<void> deleteNative(Download d) async {
    _deleted.add(d.taskId);
    // ponytail: one torrent per hash; another file of the same torrent keeps the data until it goes too.
    if (!items.any((o) => o != d && o.hash == d.hash)) {
      final id = _ids.remove(d.hash);
      if (id != null) {
        await (await _e).delete(id);
      } else {
        try {
          await Directory(await dirFor(d.hash)).delete(recursive: true);
        } on FileSystemException catch (_) {} // already gone
      }
    }
    await subtitles.remove(d.taskId);
    items.remove(d);
    await _changed();
  }

  /// The download of [file] in torrent [hash]; with no file, the one for [videoId] (or any) in that torrent.
  Download? of(String hash, int? file, [String? videoId]) {
    final h = hash.toLowerCase();
    return items
        .where((d) => d.hash == h && (file != null ? d.file == file : videoId == null || d.playback.videoId == videoId))
        .firstOrNull;
  }

  Future<void> _changed() async {
    notifyListeners();
    _watch();
    await _prefs.setString('downloads', jsonEncode([for (final d in items) d.toJson()]));
  }

  /// Polls once a second while anything is downloading, and not at all otherwise.
  void _watch() {
    if (items.any(_active)) {
      _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => refreshNative());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// One progress poll of every active download. Public for tests.
  @visibleForTesting
  Future<void> refreshNative() async {
    if (_polling) return;
    _polling = true;
    var persist = false;
    try {
      final e = await _e;
      for (final d in [...items.where(_active)]) {
        final id = _ids[d.hash];
        if (id == null) continue;
        final p = await e.progress(id);
        final state = p == null ? DownloadState.failed : downloadState(p.state);
        if (state == DownloadState.done) HapticFeedback.lightImpact();
        persist |= state != d.state || (p != null && (p.total != d.total || (p.path ?? d.path) != d.path));
        d.state = state;
        d.waiting = p?.state == 'waiting';
        if (p == null) {
          d.error = 'Download stopped';
          continue;
        }
        d
          ..bytes = p.bytes
          ..total = p.total
          ..rate = p.rate
          ..peers = p.peers
          ..error = p.error
          ..path = p.path ?? d.path;
      }
    } catch (e) {
      debugPrint('downloads poll: $e'); // the next tick tries again
    } finally {
      _polling = false;
    }
    if (persist) return _changed();
    notifyListeners();
  }

  bool _directReady = false;
  bool wifiOnly = false, networkAllowed = true;
  int? freeBytes, storedBytes;
  String? environmentError;
  Future<void>? _environmentRead;

  int get remainingBytes => [
    for (final d in items)
      if (d.state != DownloadState.done) max(0, d.total - d.bytes),
    for (final r in torrentRecords)
      if (r.info?.done != true) max(0, r.expectedFileSize - (r.info?.downloaded ?? 0)),
    for (final r in records)
      if (r.status != TaskStatus.complete && r.expectedFileSize > 0)
        (r.expectedFileSize * (1 - r.progress.clamp(0, 1))).ceil(),
  ].fold<int>(0, (sum, bytes) => sum + bytes);

  Future<void> refreshEnvironment() => _environmentRead ??=
      _readEnvironment().whenComplete(() => _environmentRead = null);

  Future<void> _readEnvironment() async {
    try {
      final m = await (await _e).downloadEnvironment();
      wifiOnly = m['wifiOnly'] == true;
      networkAllowed = m['allowed'] == true;
      freeBytes = m['free'] as int?;
      storedBytes = m['used'] as int?;
      environmentError = null;
    } catch (_) {
      environmentError = 'Could not read download network and storage. Try again.';
    } finally {
      notifyListeners();
    }
  }

  Future<void> setWifiOnly(bool on) async {
    final old = wifiOnly;
    if (!await _fd.requireWiFi(on ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks)) {
      throw StateError('Could not apply the download network choice');
    }
    try {
      await (await _e).setDownloadWifiOnly(on);
    } catch (_) {
      await _fd.requireWiFi(old ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks);
      rethrow;
    }
    await _environmentRead;
    wifiOnly = on;
    await refreshEnvironment();
  }
  final FileDownloader _fd;
  List<TaskRecord> records = [];
  final torrentRecords = <TorrentDownload>[];
  bool torrentError = false;
  late Directory _posters;
  Timer? _torrentPoll;
  bool _pollingTorrents = false;
  bool _restoringTorrents = false;
  // Cancels land asynchronously after delete() and would re-create the record.
  final _deleted = <String>{};

  Future<void> init() async {
    await load();
    _posters = Directory('${(await getApplicationDocumentsDirectory()).path}/posters');
    await _posters.create(recursive: true);
    _fd.configureNotification(
      running: const TaskNotification('Downloading', '{displayName}'),
      complete: const TaskNotification('Downloaded', '{displayName}'),
      error: const TaskNotification('Download failed', '{displayName}'),
      progressBar: true,
    );
    // Foreground mode keeps long downloads alive past Android's background limits.
    await _fd.configure(globalConfig: (Config.runInForeground, true));
    // The worker checks Content-Length against remaining capacity; unknown sizes still report write failures.
    await _fd.configure(globalConfig: (Config.checkAvailableSpace, 1));
    await refreshEnvironment();
    if (environmentError == null && !await _fd.requireWiFi(wifiOnly ? RequireWiFi.forAllTasks : RequireWiFi.forNoTasks)) {
      throw StateError('Could not restore the download network choice');
    }
    // database.updates fires after the record is stored; _fd.updates fires before.
    _fd.database.updates.listen((r) async {
      if (_deleted.contains(r.taskId)) await _fd.database.deleteRecordWithId(r.taskId);
      await refresh();
    });
    await _fd.start();
    _directReady = true;
    await refresh();
    await restoreTorrents();
  }

  Future<void> refresh() async {
    await refreshNative();
    if (!_directReady) return;
    records = await _fd.database.allRecords();
    records.sort((a, b) => b.task.creationTime.compareTo(a.task.creationTime));
    notifyListeners();
  }

  Future<void> restoreTorrents() async {
    if (_restoringTorrents) return;
    _restoringTorrents = true;
    try {
      final engine = await torrentEngine();
      final kept = await engine.resumeKept();
      final restored = [for (final k in kept) TorrentDownload(k)];
      torrentRecords
        ..clear()
        ..addAll(restored);
      torrentError = false;
      await _refreshTorrents();
    } catch (_) {
      torrentError = true;
    } finally {
      _restoringTorrents = false;
      _syncTorrentPoll();
      notifyListeners();
    }
  }

  void _syncTorrentPoll() {
    if (torrentRecords.any((r) => r.active)) {
      _torrentPoll ??= Timer.periodic(const Duration(seconds: 2), (_) => _refreshTorrents());
    } else {
      _torrentPoll?.cancel();
      _torrentPoll = null;
    }
  }

  Future<void> _refreshTorrents() async {
    if (_pollingTorrents) return;
    _pollingTorrents = true;
    try {
      final engine = await torrentEngine();
      for (final r in List<TorrentDownload>.of(torrentRecords)) {
        if (!r.active) continue;
        final status = await engine.downloadStatus(r.kept.id);
        if (torrentRecords.contains(r)) {
          r.info = status ?? const TorrentProgress(
            downloaded: 0, total: 0, done: false, error: 'This torrent is no longer available.',
          );
        }
      }
      torrentError = false;
    } catch (_) {
      // A channel failure does not turn an active native download into a terminal failure.
      torrentError = true;
    } finally {
      _pollingTorrents = false;
      _syncTorrentPoll();
      notifyListeners();
    }
  }

  Future<void> keepTorrent(TorrentEngine engine, int id, int file, {
    required String title,
    String? poster,
    required Playback playback,
    List<Subtitle> subtitles = const [],
  }) async {
    final metadata = StreamDownload(title: title, poster: poster, playback: playback, subtitles: subtitles);
    final kept = await engine.keep(id, file, titleJson: metadata.toMetaData());
    _deleted.remove(kept.taskId);
    torrentRecords.removeWhere((r) => r.taskId == kept.taskId);
    torrentRecords.add(TorrentDownload(kept));
    _syncTorrentPoll();
    notifyListeners();
    unawaited(_refreshTorrents());
    if (poster != null) unawaited(_cachePoster(kept.taskId, poster));
  }

  StreamDownload? streamOf(TaskRecord r) => StreamDownload.fromMetaData(r.task.metaData);

  File posterOf(String itemId) => File('${_posters.path}/$itemId.jpg');

  TaskRecord? recordFor(String itemId) =>
      records.where((r) => r.task.taskId == itemId).firstOrNull;

  /// Local file path if [itemId] is fully downloaded.
  Future<String?> localPath(String itemId) async {
    final torrent = torrentRecords.where((r) => r.taskId == itemId).firstOrNull;
    if (torrent != null) {
      final path = torrent.info?.path;
      return torrent.info?.done == true && path != null && File(path).existsSync() ? path : null;
    }
    final r = recordFor(itemId);
    if (r == null || r.status != TaskStatus.complete) return null;
    final path = await r.task.filePath();
    return File(path).existsSync() ? path : null;
  }

  Future<void> enqueueStream({
    required String url,
    Map<String, String> headers = const {},
    required String title,
    String? poster,
    required Playback playback,
    List<Subtitle> subtitles = const [],
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
      requiresWiFi: wifiOnly,
      retries: 5,
      displayName: playback.subtitle == null ? title : '$title · ${playback.subtitle}',
      metaData: StreamDownload(title: title, poster: poster, playback: playback, subtitles: subtitles).toMetaData(),
    );
    if (!await _fd.enqueue(task)) throw StateError('Download was not queued');
    await refresh();
    if (poster != null) await _cachePoster(taskId, poster);
  }

  Future<void> _cachePoster(String taskId, String poster) async {
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

  Future<void> pause(Object r) async {
    if (r is Download) return pauseNative(r);
    await _fd.pause((r as TaskRecord).task as DownloadTask);
  }
  Future<void> resume(Object r) async {
    if (r is Download) return resumeNative(r);
    await _fd.resume((r as TaskRecord).task as DownloadTask);
  }

  Future<void> retry(TaskRecord r) async {
    if (!await _fd.enqueue(r.task.copyWith(retries: 5))) throw StateError('Download was not queued');
    await refresh();
  }

  Future<void> retryTorrent(TorrentDownload r) async {
    await (await _e).resume(r.kept.id);
    r.info = null;
    await _refreshTorrents();
  }

  Future<OfflineSubtitle> saveSubtitle(String id, {required String text, required String label, required String lang}) async {
    final saved = await subtitles.save(id, text: text, label: label, lang: lang, exists: () =>
      !_deleted.contains(id) && (items.any((d) => d.taskId == id) ||
        records.any((r) => r.taskId == id) || torrentRecords.any((r) => r.taskId == id)));
    notifyListeners();
    return saved;
  }

  Future<void> removeSubtitle(String id) async {
    await subtitles.remove(id);
    notifyListeners();
  }

  Future<void> delete(Object record) async {
    if (record is Download) return deleteNative(record);
    final r = record as TaskRecord;
    _deleted.add(r.taskId);
    await _fd.cancelTaskWithId(r.taskId);
    final f = File(await r.task.filePath());
    if (f.existsSync()) await f.delete();
    await subtitles.remove(r.taskId);
    final p = posterOf(r.taskId);
    if (p.existsSync()) await p.delete();
    await _fd.database.deleteRecordWithId(r.taskId);
    await refresh();
  }

  Future<void> deleteTorrent(TorrentDownload r) async {
    _deleted.add(r.taskId);
    final engine = await _e;
    await engine.remove(r.kept.id);
    await subtitles.remove(r.taskId);
    torrentRecords.remove(r);
    final p = posterOf(r.taskId);
    if (p.existsSync()) await p.delete();
    _syncTorrentPoll();
    notifyListeners();
  }

  Future<int> bytesUsed() async {
    var total = 0;
    for (final r in records) {
      final f = File(await r.task.filePath());
      if (f.existsSync()) total += await f.length();
    }
    for (final r in torrentRecords) {
      total += r.info?.downloaded ?? 0;
    }
    for (final d in items) {
      total += d.state == DownloadState.done ? d.total : d.bytes;
    }
    return total;
  }

  @override
  void dispose() {
    _torrentPoll?.cancel();
    _poll?.cancel();
    super.dispose();
  }
}

String _reason(Object e) => e is PlatformException ? e.message ?? e.code : '$e';
