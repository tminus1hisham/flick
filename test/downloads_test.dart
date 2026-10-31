import 'dart:io';

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
  NativeTorrentProgress? Function(int id) progressOf = (_) => null;

  @override
  Future<int> add(String magnet, String dir) async {
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
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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

    e.progressOf = (_) => (bytes: 200, total: 200, rate: 0, peers: 0, state: 'done', error: null, path: file.path);
    await a.refresh();
    expect((d.state, d.path), (DownloadState.done, file.path));

    final again = _Engine();
    final b = _downloads(again);
    await b.load();
    expect(again.calls, isEmpty);
    expect((b.items.single.state, b.items.single.path), (DownloadState.done, file.path));
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
