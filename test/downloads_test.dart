import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:background_downloader/src/permissions.dart' show Permissions;
import 'package:flick/downloads.dart';
import 'package:flick/playback.dart';
import 'package:flick/torrent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _hash = 'ed0afbc1a2b3c4d5e6f708192a3b4c5d6e7f8091';
const _magnet = 'magnet:?xt=urn:btih:ED0AFBC1A2B3C4D5E6F708192A3B4C5D6E7F8091&dn=Rick';
const Playback _ep =
    (title: 'Rick and Morty', subtitle: 'S4 E2', logo: 'https://img/logo.png', poster: 'https://img/p.jpg', meta: null, type: 'series', videoId: 'tt1:4:2', season: 4, episode: 2);

/// Records channel calls; [progressOf] answers progress.
class _Engine implements TorrentEngine {
  final calls = <String>[];
  bool wifiOnly = false, failPolicy = false;
  Future<Map<String, Object?>> Function()? environmentOf;
  NativeTorrentProgress? Function(int id) progressOf = (_) => null;

  @override
  Future<int> add(String magnet, String dir, {bool downloadOnly = false}) async {
    expect(downloadOnly, isTrue, reason: 'Restored and new downloads must apply the network rule before metadata');
    calls.add('add $dir');
    return 7;
  }

  @override
  Future<void> download(int id, int file) async => calls.add('download $id $file');
  @override
  Future<void> pause(int id) async => calls.add('pause $id');
  @override
  Future<void> resume(int id) async => calls.add('resume $id');
  @override
  Future<void> delete(int id) async => calls.add('delete $id');
  @override
  Future<bool> requestNotifications() async => true;
  @override
  Future<NativeTorrentProgress?> progress(int id) async => progressOf(id);

  @override
  Future<Map<String, Object?>> downloadEnvironment() async => environmentOf?.call() ?? {
    'wifiOnly': wifiOnly, 'allowed': !wifiOnly, 'free': 1000, 'used': 200,
  };

  @override
  Future<void> setDownloadWifiOnly(bool on) async {
    if (failPolicy) throw StateError('disk full');
    wifiOnly = on;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Permissions implements Permissions {
  @override
  Future<PermissionStatus> request(PermissionType type) async => PermissionStatus.granted;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloader implements FileDownloader {
  final policies = <RequireWiFi>[];
  final tasks = <Task>[];
  bool acceptPolicy = true;
  @override
  Permissions get permissions => _Permissions();
  @override
  Future<bool> requireWiFi(RequireWiFi requirement, {
    dynamic rescheduleRunningTasks = true, dynamic alsoRestartUploads = false,
  }) async {
    expect(rescheduleRunningTasks, isTrue);
    policies.add(requirement);
    return acceptPolicy;
  }
  @override
  Future<bool> enqueue(Task task) async { tasks.add(task); return true; }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Downloads _downloads(_Engine e) {
  final d = Downloads(engine: e, dirFor: (h) async => 'dl/$h');
  addTearDown(d.dispose);
  return d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('engine progress states map to download states', () {
    expect(downloadState('downloading'), DownloadState.downloading);
    expect(downloadState('paused'), DownloadState.paused);
    expect(downloadState('done'), DownloadState.done);
    expect(downloadState('error'), DownloadState.failed);
  });

  test('network choice reaches HTTP and native engines and reloads with capacity', () async {
    final e = _Engine();
    final http = _Downloader();
    final d = Downloads(engine: e, downloader: http);
    addTearDown(d.dispose);
    await d.setWifiOnly(true);
    expect(http.policies, [RequireWiFi.forAllTasks]);
    expect((e.wifiOnly, d.wifiOnly, d.networkAllowed, d.freeBytes, d.storedBytes), (true, true, false, 1000, 200));
    final restarted = Downloads(engine: e, downloader: http);
    addTearDown(restarted.dispose);
    await restarted.refreshEnvironment();
    expect(restarted.wifiOnly, isTrue);
    await restarted.setWifiOnly(false);
    expect(http.policies.last, RequireWiFi.forNoTasks);
    expect((e.wifiOnly, restarted.networkAllowed), (false, true));
  });

  test('a refused policy leaves the preference intact and native failure rolls HTTP back', () async {
    final e = _Engine();
    final http = _Downloader()..acceptPolicy = false;
    final d = Downloads(engine: e, downloader: http);
    addTearDown(d.dispose);
    await expectLater(d.setWifiOnly(true), throwsStateError);
    expect(e.wifiOnly, isFalse);
    http.acceptPolicy = true;
    e.failPolicy = true;
    await expectLater(d.setWifiOnly(true), throwsStateError);
    expect(http.policies.last, RequireWiFi.forNoTasks);
    expect(d.wifiOnly, isFalse);
  });

  test('a pending storage refresh cannot overwrite a successful network choice', () async {
    final e = _Engine();
    final pending = Completer<Map<String, Object?>>();
    e.environmentOf = () => pending.future;
    final d = Downloads(engine: e, downloader: _Downloader());
    addTearDown(d.dispose);
    final refresh = d.refreshEnvironment();
    final change = d.setWifiOnly(true);
    await Future<void>.delayed(Duration.zero);
    expect(e.wifiOnly, isTrue);
    e.environmentOf = null;
    pending.complete({'wifiOnly': false, 'allowed': true, 'free': 1000, 'used': 200});
    await Future.wait([refresh, change]);
    expect((d.wifiOnly, d.networkAllowed), (true, false));
  });

  test('new HTTP tasks and retries retain identity and headers under the network choice', () async {
    final e = _Engine();
    final http = _Downloader();
    final d = Downloads(engine: e, downloader: http);
    addTearDown(d.dispose);
    await d.load();
    await d.setWifiOnly(true);
    await d.enqueueStream(url: 'https://video.test/file.mp4', headers: {'Authorization': 'video-only'},
      title: _ep.title, playback: _ep);
    final task = http.tasks.single;
    expect(task.requiresWiFi, isTrue);
    expect(task.headers, {'Authorization': 'video-only'});
    expect(StreamDownload.fromMetaData(task.metaData)!.playback.videoId, _ep.videoId);
    await d.retry(TaskRecord(task, TaskStatus.failed, -1, -1));
    expect(http.tasks.last.taskId, task.taskId);
    expect(http.tasks.last.headers, task.headers);
  });

  test('network waiting remains active and does not become a user pause', () async {
    final e = _Engine();
    final d = _downloads(e);
    await d.load();
    await d.start(_magnet, _ep, 3);
    e.progressOf = (_) => (bytes: 20, total: 100, rate: 0, peers: 0, state: 'waiting', error: null, path: null);
    await d.refreshNative();
    expect((d.items.single.state, d.items.single.waiting), (DownloadState.downloading, true));
    e.progressOf = (_) => (bytes: 25, total: 100, rate: 5, peers: 1, state: 'downloading', error: null, path: null);
    await d.refreshNative();
    expect(d.items.single.waiting, isFalse);
    expect(TorrentProgress.fromStatus({'waiting': true}).waiting, isTrue);
  });

  test('capacity warning counts known unfinished bytes and ignores unknown and finished sizes', () async {
    final d = _downloads(_Engine());
    await d.load();
    final partial = Download(hash: _hash, magnet: _magnet, file: 0, playback: _ep, total: 100)..bytes = 30;
    d.items.add(partial);
    final task = DownloadTask(url: 'https://video.test/file');
    d.records = [TaskRecord(task, TaskStatus.running, 0.25, 200),
      TaskRecord(task, TaskStatus.complete, 1, 500), TaskRecord(task, TaskStatus.running, -1, -1)];
    expect(d.remainingBytes, 220);
    partial.state = DownloadState.done;
    expect(d.remainingBytes, 150);
  });

  test('an unfinished download survives a restart and is added to the engine again', () async {
    final first = _Engine();
    final a = _downloads(first);
    await a.load();
    await a.start(_magnet, _ep, 3, poster: 'https://img/p.jpg');
    expect(first.calls, ['add dl/$_hash', 'download 7 3']);

    final second = _Engine();
    final b = _downloads(second);
    await b.load();
    expect(second.calls, ['add dl/$_hash', 'download 7 3']);
    final d = b.items.single;
    expect((d.hash, d.file, d.poster, d.playback, d.state), (_hash, 3, 'https://img/p.jpg', _ep, DownloadState.queued));
    expect(b.of(_hash.toUpperCase(), 3), same(d));
    expect(b.of(_hash, null, 'tt1:4:2'), same(d));
    expect(b.of(_hash, null, 'tt1:4:3'), isNull);
  });

  test('a poll maps progress onto the download; done keeps its path, and a finished file is not added again',
      () async {
    final file = File('${Directory.systemTemp.createTempSync('flick').path}/kid.mkv')..writeAsStringSync('x');
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final e = _Engine();
    final a = _downloads(e);
    await a.load();
    await a.start(_magnet, _ep, 0);

    e.progressOf = (_) => (bytes: 50, total: 200, rate: 9, peers: 4, state: 'downloading', error: null, path: null);
    await a.refresh();
    final d = a.items.single;
    expect((d.state, d.bytes, d.total, d.rate, d.peers), (DownloadState.downloading, 50, 200, 9, 4));
    expect(await a.bytesUsed(), 50);

    e.progressOf = (_) => (bytes: 200, total: 200, rate: 0, peers: 0, state: 'done', error: null, path: file.path);
    await a.refresh();
    expect((d.state, d.path), (DownloadState.done, file.path));
    expect(await a.bytesUsed(), 200);

    final again = _Engine();
    final b = _downloads(again);
    await b.load();
    expect(again.calls, isEmpty);
    expect((b.items.single.state, b.items.single.path), (DownloadState.done, file.path));
    expect(await b.bytesUsed(), 200);
  });

  test('delete removes the download and deletes it in the engine', () async {
    final e = _Engine();
    final a = _downloads(e);
    await a.load();
    await a.start(_magnet, _ep, 3);
    await a.delete(a.items.single);
    expect(e.calls.last, 'delete 7');
    expect(a.items, isEmpty);

    final b = _downloads(_Engine());
    await b.load();
    expect(b.items, isEmpty);
  });
  test('pause and resume dispatch to the native engine and restore paused state', () async {
    final engine = _Engine();
    final manager = _downloads(engine);
    await manager.load();
    await manager.start(_magnet, _ep, 3);
    final d = manager.items.single;
    await manager.pause(d);
    expect(engine.calls.last, 'pause 7');
    expect(d.state, DownloadState.paused);

    final restartedEngine = _Engine();
    final restarted = _downloads(restartedEngine);
    await restarted.load();
    expect(restartedEngine.calls.last, 'pause 7');
    expect(restarted.items.single.state, DownloadState.paused);
    await restarted.resume(restarted.items.single);
    expect(restartedEngine.calls.last, 'resume 7');
    expect(restarted.items.single.state, DownloadState.queued);
  });

}
