import 'dart:convert';

import 'package:flick/addons.dart';
import 'package:flick/queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final provider = Addon({'id': 'queue', 'name': 'Queue provider'}, 'https://provider.example');
AddonStream source({String? hash, int? file, String? name = '1080p', String? release = 'Release',
  String? filename, String? group, String url = 'https://media.example/fresh?token=secret', String? external}) => (
  name: name, title: release, infoHash: hash, fileIdx: file, filename: filename, bingeGroup: group,
  url: hash == null ? url : null, externalUrl: external, trackers: <String>[],
  headers: {'Authorization': 'private'}, subtitles: <Subtitle>[], videoSize: null, videoHash: null);
QueuedMovie movie(String id) => QueuedMovie.fromStream(id, 'Movie $id', null, provider, source());

class _FailQueue extends MovieQueue {
  bool failing = true;
  @override
  Future<bool> persist(String value) => failing ? Future.value(false) : super.persist(value);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('movie queue persists order and choice without resolved URLs, headers or subtitles', () async {
    final queue = MovieQueue();
    await queue.load();
    final a = movie('tt1'), b = movie('tt2');
    expect(await queue.add(a), isTrue);
    expect(await queue.add(movie('tt1')), isFalse);
    await queue.add(b);
    await queue.move(b, -1);
    final restored = MovieQueue();
    await restored.load();
    expect(restored.items.map((m) => m.id), ['tt2', 'tt1']);
    expect(restored.items.first.name, '1080p');
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('movieQueue')!;
    expect(json, isNot(contains('media.example')));
    expect(json, isNot(contains('Authorization')));
    expect(json, isNot(contains('secret')));
    expect(json, isNot(contains('subtitles')));
    await restored.remove(restored.items.first);
    await restored.move(restored.items.first, -1);
    await restored.move(restored.items.first, 1);
    expect(restored.items.single.id, 'tt1');
    await restored.clear();
    await queue.load();
    expect(queue.items, isEmpty);
  });

  test('malformed entries and duplicates do not discard valid pending movies', () async {
    SharedPreferences.setMockInitialValues({'movieQueue': jsonEncode([
      movie('tt1').toJson(), {'id': 'bad'}, movie('tt1').toJson(), movie('tt2').toJson(),
      {...movie('tt3').toJson(), 'start': -1},
    ])});
    final queue = MovieQueue();
    await queue.load();
    expect(queue.items.map((m) => m.id), ['tt1', 'tt2']);
    for (final malformed in ['not json', '{}', 'null']) {
      SharedPreferences.setMockInitialValues({'movieQueue': malformed});
      await queue.load();
      expect(queue.items, isEmpty);
    }
  });

  test('failed saves remain actionable and retry saves current registry after clear', () async {
    final queue = _FailQueue();
    await queue.load();
    await queue.add(movie('tt1'));
    expect(queue.error, isNotNull);
    expect(queue.items, hasLength(1));
    await queue.clear();
    expect(queue.error, isNotNull);
    queue.failing = false;
    await queue.save();
    expect(queue.error, isNull);
    final restored = MovieQueue();
    await restored.load();
    expect(restored.items, isEmpty);
  });

  test('concurrent mutations persist the latest queue rather than an older snapshot', () async {
    final queue = MovieQueue();
    await queue.load();
    await Future.wait([queue.add(movie('tt1')), queue.add(movie('tt2')), queue.clear(), queue.add(movie('tt3'))]);
    final restored = MovieQueue();
    await restored.load();
    expect(restored.items.map((m) => m.id), ['tt3']);
  });

  test('source matching refreshes URLs but refuses ambiguous, changed and external choices', () {
    final item = movie('tt1');
    final fresh = source(url: 'https://media.example/renewed');
    expect(item.match([fresh])?.url, fresh.url);
    expect(item.match([fresh, fresh]), isNull);
    expect(item.match([source(release: 'Other language')]), isNull);
    expect(item.match([source(name: '720p')]), isNull);
    expect(item.match([source(group: 'Other group')]), isNull);
    expect(item.match([source(external: 'https://service.example')]), isNull);
    final file = QueuedMovie.fromStream('tt1', 'Movie', null, provider, source(filename: 'movie.mkv', group: 'g'));
    expect(file.match([source(filename: 'movie.mkv', group: 'g', release: 'New seed count')]), isNotNull);
    expect(file.match([source(filename: 'dub.mkv', group: 'g')]), isNull);
    final anonymous = QueuedMovie.fromStream('tt1', 'Movie', null, provider, source(name: null, release: null));
    expect(anonymous.match([source(name: null, release: null)]), isNull);
  });

  test('torrent matching uses both hash and file index', () {
    final item = QueuedMovie.fromStream('tt1', 'Movie', null, provider, source(hash: 'ABC', file: 2));
    expect(item.match([source(hash: 'abc', file: 2)])?.fileIdx, 2);
    expect(item.match([source(hash: 'abc', file: 3)]), isNull);
    expect(item.match([source(hash: 'other', file: 2)]), isNull);
    expect(item.match([source(hash: 'abc', file: 2), source(hash: 'abc', file: 2)]), isNull);
  });

  test('only started, successful completion advances once; failures and early stops can retry', () {
    final progress = MovieQueueProgress();
    bool finish({bool done = true, bool early = false, bool failed = false, bool next = true}) =>
      progress.completed(done: done, stoppedEarly: early, failed: failed, hasNext: next);
    expect(finish(), isFalse);
    expect(progress.started(), isTrue);
    expect(progress.started(), isFalse);
    expect(finish(done: false), isFalse);
    expect(finish(early: true), isFalse);
    expect(finish(failed: true), isFalse);
    expect(finish(next: false), isFalse);
    expect(finish(), isTrue);
    expect(finish(), isFalse);
  });

  test('live queue is ordered, deduplicated by sport/event and session only', () {
    final queue = LiveQueue();
    final a = (id: 1, sport: 1, name: 'Game', league: 'League', start: DateTime(2026), status: 10);
    final b = (id: 1, sport: 2, name: 'Other sport', league: 'League', start: DateTime(2026), status: 10);
    expect(queue.add(a), isTrue);
    expect(queue.add(a), isFalse);
    queue.add(b);
    queue.move(b, -1);
    expect(queue.items, [b, a]);
    queue.move(b, -1);
    queue.remove(a);
    expect(queue.items, [b]);
    expect(LiveQueue().items, isEmpty);
  });

  test('completion waits for an open panel and releases exactly once after it closes', () {
    final progress = MovieQueueProgress()..started();
    expect(progress.completed(done: true, stoppedEarly: false, failed: false, hasNext: true, panelOpen: true), isFalse);
    expect(progress.release(panelOpen: true), isFalse);
    expect(progress.release(panelOpen: false), isTrue);
    expect(progress.release(panelOpen: false), isFalse);
    expect(progress.completed(done: true, stoppedEarly: false, failed: false, hasNext: true), isFalse);
  });

  test('custom movie IDs stay provider scoped while IMDb movies deduplicate across providers', () async {
    final queue = MovieQueue();
    await queue.load();
    final other = Addon({'id': 'other', 'name': 'Other'}, 'https://other.example');
    await queue.add(movie('custom:1'));
    expect(await queue.add(QueuedMovie.fromStream('custom:1', 'Other movie', null, other, source())), isTrue);
    expect(queue.items.first.sameMovie('custom:1', other.base), isFalse);
    expect(queue.items.first.sameMovie('custom:1', null), isFalse);
    await queue.add(movie('tt1'));
    expect(await queue.add(QueuedMovie.fromStream('tt1', 'Same movie', null, other, source())), isFalse);
    final restored = MovieQueue();
    await restored.load();
    expect(restored.items, hasLength(3));
  });
}
