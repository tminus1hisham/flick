import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback.dart';
import 'torrent.dart';

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
      this.path = '', this.state = DownloadState.queued, this.total = 0});
  final String hash, magnet;
  final int file;
  final Playback playback;
  final String? poster;
  String path;
  DownloadState state;
  int bytes = 0, total, rate = 0, peers = 0;
  String? error;

  Map<String, Object?> toJson() => {
        'hash': hash, 'magnet': magnet, 'file': file, 'poster': poster, 'path': path, 'state': state.name,
        'total': total,
        'playback': {
          'title': playback.title, 'subtitle': playback.subtitle, 'type': playback.type,
          'videoId': playback.videoId, 'season': playback.season, 'episode': playback.episode,
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
      playback: (
        title: p['title'] as String,
        subtitle: p['subtitle'] as String?,
        type: p['type'] as String,
        videoId: p['videoId'] as String,
        season: p['season'] as int?,
        episode: p['episode'] as int?,
      ),
    );
  }
}

/// The download registry: persisted in shared_preferences, driven through the torrent engine.
class Downloads extends ChangeNotifier {
  /// [engine] and [dirFor] are seams for tests.
  Downloads({TorrentEngine? engine, this.dirFor = downloadDir}) : _engine = engine;
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
    final id = await e.add(d.magnet, await dirFor(d.hash));
    _ids[d.hash] = id;
    await e.download(id, d.file);
  }

  /// Registers [file] of [magnet]. Throws, with nothing listed, when the engine refuses it.
  Future<void> start(String magnet, Playback playback, int file, {String? poster}) async {
    final hash = infoHashOf(magnet)!;
    final old = of(hash, file);
    if (old != null && old.state != DownloadState.failed) return;
    final d = Download(hash: hash, magnet: magnet, file: file, playback: playback, poster: poster);
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

  Future<void> pause(Download d) async {
    await (await _e).pause(_ids[d.hash]!);
    d.state = DownloadState.paused;
    await _changed();
  }

  /// Resumes a paused download; a failed one (or one the engine lost) is added and pinned again.
  Future<void> resume(Download d) async {
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

  Future<void> delete(Download d) async {
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
      _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => refresh());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// One progress poll of every active download. Public for tests.
  @visibleForTesting
  Future<void> refresh() async {
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

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}

String _reason(Object e) => e is PlatformException ? e.message ?? e.code : '$e';
