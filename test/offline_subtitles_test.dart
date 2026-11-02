import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flick/downloads.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/offline_subtitles.dart';
import 'package:flick/playback.dart';
import 'package:flick/screens/offline_subtitles.dart';
import 'package:flick/screens/player.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/torrent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _text = '1\n00:00:01,000 --> 00:00:03,000\nCafé 日本語\n';
const _source = (id: 'english', url: 'https://subtitles.test/one.srt', lang: 'eng');
const Playback _playback = (title: 'Film', subtitle: null, logo: null, poster: null, type: 'movie',
  videoId: 'tt1', season: null, episode: null, scope: null, meta: null);

class _Store extends OfflineSubtitles {
  _Store(Directory dir) : super(directory: () async => dir);
  int writes = 0;
  int? failAt;
  Completer<void>? hold, reached;
  @override
  Future<bool> persist(String value) async {
    if (++writes == failAt) return false;
    final result = await super.persist(value);
    if (hold != null) { reached!.complete(); await hold!.future; hold = null; }
    return result;
  }
}

class _Engine implements TorrentEngine {
  @override
  Future<void> remove(int id, {bool unlessKept = false}) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Database implements Database {
  @override
  Future<void> deleteRecordWithId(String taskId) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Downloader implements FileDownloader {
  @override
  final database = _Database();
  @override
  Future<bool> cancelTaskWithId(String id) async => true;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
class _Downloads extends Downloads {
  _Downloads(this.root, OfflineSubtitles store) : super(subtitles: store, engine: _Engine(), downloader: _Downloader(),
    dirFor: (_) async => '${root.path}/video');
  final Directory root;
  @override
  File posterOf(String id) => File('${root.path}/missing-poster');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, dir;
  late _Store store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('offline-subtitles');
    dir = Directory('${root.path}/captions');
    store = _Store(dir);
  });
  tearDown(() async { device.tv = false; await root.delete(recursive: true); });

  Future<OfflineSubtitle> save(String id, {String text = _text, String label = 'English'}) =>
      store.save(id, text: text, label: label, lang: 'en', exists: () => true);

  test('saved subtitle survives restart without storing a remote URL or credentials', () async {
    final saved = await save('video');
    final restored = OfflineSubtitles(directory: () async => dir);
    expect(await (await restored.get('video'))!.read(), _text);
    expect((await restored.get('video'))!.subtitle.url, Uri.file(saved.path).toString());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('downloadSubtitles'), isNot(contains('https://')));
    expect(prefs.getString('downloadSubtitles'), isNot(contains('Authorization')));
    await restored.remove('video');
    expect(await File(saved.path).exists(), isFalse);
    expect(await restored.get('video'), isNull);
  });

  test('replacement cleans old files and removing one download leaves other captions', () async {
    final old = await save('one');
    final other = await save('two');
    final replacement = await save('one', text: 'Replacement', label: 'French');
    expect(await File(old.path).exists(), isFalse);
    expect(await replacement.read(), 'Replacement');
    await store.remove('one');
    expect(await File(replacement.path).exists(), isFalse);
    expect(await other.read(), _text);
    expect(await store.get('one'), isNull);
  });

  test('failed final metadata write keeps the old caption and journals cleanup across restart', () async {
    final old = await save('video');
    store.failAt = store.writes + 2;
    await expectLater(save('video', text: 'New'), throwsStateError);
    final restarted = OfflineSubtitles(directory: () async => dir);
    expect((await restarted.get('video'))!.path, old.path);
    expect(await (await restarted.get('video'))!.read(), _text);
    expect(await dir.list().length, 2);
    await restarted.remove('video');
    expect(await dir.list().isEmpty, isTrue);
  });

  test('deletion during a save cleans the interrupted file without recreating its registry entry', () async {
    var exists = true;
    store.hold = Completer<void>();
    store.reached = Completer<void>();
    final saving = store.save('video', text: _text, label: 'English', lang: 'en', exists: () => exists);
    final failed = expectLater(saving, throwsStateError);
    await store.reached!.future;
    exists = false;
    final deleting = store.remove('video');
    store.hold!.complete();
    await Future.wait([failed, deleting]);
    expect(await store.get('video'), isNull);
    expect(await dir.list().isEmpty, isTrue);
  });

  test('damaged metadata cannot delete outside the sidecar directory or discard valid captions', () async {
    await save('valid');
    final outside = File('${root.path}/outside.srt')..writeAsStringSync('Keep me');
    final prefs = await SharedPreferences.getInstance();
    final records = jsonDecode(prefs.getString('downloadSubtitles')!) as Map;
    records['bad'] = {'file': '../outside.srt', 'files': ['../outside.srt'], 'label': 'Bad', 'lang': 'en'};
    records['broken'] = null;
    await prefs.setString('downloadSubtitles', jsonEncode(records));
    final restarted = OfflineSubtitles(directory: () async => dir);
    expect(await (await restarted.get('valid'))!.read(), _text);
    expect(await restarted.get('bad'), isNull);
    await restarted.remove('bad');
    expect(await outside.readAsString(), 'Keep me');
  });

  test('empty, oversized and missing files fail visibly without replacing a good caption', () async {
    final saved = await save('video');
    await expectLater(save('video', text: ' '), throwsFormatException);
    await expectLater(save('video', text: 'x' * (maxOfflineSubtitleBytes + 1)), throwsFormatException);
    expect(await saved.read(), _text);
    await File(saved.path).delete();
    await expectLater((await store.get('video'))!.read(), throwsA(isA<FileSystemException>()));
    await store.remove('video');
  });

  test('external requests isolate headers, decode legacy text and reject local URLs', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.headers['authorization'], isNull);
      expect(request.headers['cookie'], isNull);
      expect(request.headers['referer'], isNull);
      return http.Response.bytes([67, 97, 102, 233], 200);
    });
    expect(await readExternalSubtitle(_source.url, client: client), 'Café');
    await expectLater(readExternalSubtitle('file:///private/secret', client: client), throwsFormatException);
    expect(calls, 1);
  });

  test('subtitle HTTP errors and oversized chunked bodies are rejected', () async {
    await expectLater(readExternalSubtitle(_source.url,
      client: MockClient((_) async => http.Response('Failure', 503))), throwsStateError);
    final client = MockClient.streaming((_, _) async => http.StreamedResponse(Stream.fromIterable([
      List.filled(maxOfflineSubtitleBytes, 65), [66],
    ]), 200));
    await expectLater(readExternalSubtitle(_source.url, client: client), throwsFormatException);
  });

  test('saved local captions win offline without overriding Off or a current explicit choice', () {
    final local = (track: SubtitleTrack('file:///local.srt', 'Saved', 'und'), url: 'file:///local.srt', lang: 'und', label: 'Saved', detail: 'Offline');
    final online = (track: SubtitleTrack('https://subs.test/one', 'Online', 'en'), url: 'https://subs.test/one', lang: 'en', label: 'Online', detail: '');
    Caption? pick({String? preference, Caption? choice}) => preferredCaption([online, local], preference: preference,
      choice: choice, deviceLanguage: 'en', audioLanguage: 'en', selectedId: 'auto', savedUrl: local.url);
    expect(pick(), local);
    expect(pick(preference: 'off')!.track.id, 'no');
    expect(pick(choice: online), online);
  });

  test('download metadata keeps supplied subtitle candidates and reads older records', () {
    const stream = StreamDownload(title: 'Film', playback: _playback, subtitles: [_source]);
    expect(StreamDownload.fromMetaData(stream.toMetaData())!.subtitles, [_source]);
    final json = jsonDecode(stream.toMetaData()) as Map;
    json.remove('subtitles');
    expect(StreamDownload.fromMetaData(jsonEncode(json))!.subtitles, isEmpty);
    final native = Download(hash: 'hash', magnet: 'magnet', file: 0, playback: _playback, subtitles: [_source]);
    expect(Download.fromJson(native.toJson()).subtitles, [_source]);
  });

  for (final kind in ['http', 'kept', 'legacy']) {
    test('$kind video deletion removes its saved subtitle', () async {
      final manager = _Downloads(root, store);
      addTearDown(manager.dispose);
      await manager.load();
      final videoDir = Directory('${root.path}/video')..createSync();
      final video = File('${videoDir.path}/film.mp4')..writeAsStringSync('Fixture');
      final record = TaskRecord(DownloadTask(taskId: 'http', url: 'https://video.test/film', filename: 'film.mp4',
        directory: videoDir.path, baseDirectory: BaseDirectory.root), TaskStatus.complete, 1, 7);
      final legacy = Download(hash: 'hash', magnet: 'magnet', file: 0, playback: _playback,
        path: video.path, state: DownloadState.done);
      final kept = TorrentDownload(KeptTorrent(id: 1, infoHash: 'hash', magnet: 'magnet', file: 0, dir: videoDir.path,
        titleJson: const StreamDownload(title: 'Film', playback: _playback).toMetaData(), name: 'film.mp4', size: 7, done: true));
      final id = kind == 'http' ? record.taskId : kind == 'kept' ? kept.taskId : legacy.taskId;
      if (kind == 'http') manager.records.add(record);
      if (kind == 'kept') manager.torrentRecords.add(kept);
      if (kind == 'legacy') manager.items.add(legacy);
      final saved = await manager.saveSubtitle(id, text: _text, label: 'English', lang: 'en');
      if (kind == 'http') await manager.delete(record);
      if (kind == 'kept') await manager.deleteTorrent(kept);
      if (kind == 'legacy') await manager.deleteNative(legacy);
      expect(await File(saved.path).exists(), isFalse);
      expect(await store.get(id), isNull);
      await expectLater(manager.saveSubtitle(id, text: _text, label: 'English', lang: 'en'), throwsStateError);
    });
  }

  for (final tv in [false, true]) {
    testWidgets('offline save errors, Retry and removal fit larger text, tv=$tv', (tester) async {
      device.tv = tv;
      tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var saved = false, fail = true;
      var saves = 0;
      await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)), child: child!),
        home: Scaffold(body: SizedBox(width: tv ? 380 : 180, child: StatefulBuilder(builder: (context, change) => ListView(children: [
          OfflineSubtitleControls(saved: saved, save: () async {
            saves++; if (fail) throw StateError('Storage full'); change(() => saved = true);
          }, remove: () async { change(() => saved = false); }, findOnline: () async {}),
        ]))))));
      Future<void> activate(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        if (tv) {
          final detector = find.descendant(of: find.widgetWithText(FocusFrame, label), matching: find.byType(FocusableActionDetector));
          tester.widget<FocusableActionDetector>(detector).focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else { await tester.tap(find.text(label)); }
        await tester.pumpAndSettle();
      }
      await activate('Save subtitle offline');
      expect(find.textContaining('Could not update'), findsOneWidget);
      fail = false;
      await activate('Retry offline subtitle');
      expect(saves, 2);
      expect(saved, isTrue);
      expect(find.textContaining('Subtitle saved'), findsOneWidget);
      if (tv) expect(FocusManager.instance.primaryFocus?.debugLabel, 'Offline subtitle search');
      await activate('Remove saved subtitle');
      expect(saved, isFalse);
      if (tv) expect(FocusManager.instance.primaryFocus?.debugLabel, 'Offline subtitle search');
      expect(tester.takeException(), isNull);
    });
  }
}
