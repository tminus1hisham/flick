import 'dart:convert';

import 'package:flick/history.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

WatchProgress progress({String type = 'series', String id = 'tt123:1:2',
    int seconds = 123, int duration = 1200}) => WatchProgress(
  type: type, videoId: id, title: 'A title', subtitle: 'Episode 2', poster: null,
  position: Duration(seconds: seconds), duration: Duration(seconds: duration),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a seek to zero clears progress, but temporary open/close zeroes do not', () {
    expect(watchPosition(Duration.zero, started: true, opening: false, completed: false), Duration.zero);
    expect(watchPosition(Duration.zero, started: false, opening: true, completed: false), isNull);
    expect(watchPosition(Duration.zero, started: true, opening: true, completed: false), isNull);
    expect(watchPosition(Duration.zero, started: true, opening: false, completed: true), isNull);
    expect(watchPosition(const Duration(seconds: 123), started: false, opening: true, completed: false),
      const Duration(seconds: 123));
    expect(watchPosition(const Duration(seconds: -1), started: true, opening: false, completed: false), isNull);
  });

  test('progress survives restart without storing a stream URL or credentials', () async {
    final history = ViewingHistory();
    await history.load();
    await history.save(progress());
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.position('series', 'tt123:1:2'), const Duration(seconds: 123));
    expect(restored.entries.single.title, 'A title');
    expect(restored.entries.single.subtitle, 'Episode 2');
    final prefs = await SharedPreferences.getInstance();
    final stored = (jsonDecode(prefs.getString('viewingHistory')!) as List).single as Map;
    expect(stored.keys, unorderedEquals(['type', 'videoId', 'title', 'subtitle', 'poster', 'position', 'duration']));
  });

  test('content IDs separate episodes, types and provider namespaces', () async {
    final history = ViewingHistory();
    await history.load();
    for (final p in [progress(), progress(id: 'tt123:1:3', seconds: 200),
      progress(type: 'movie', seconds: 300), progress(id: 'kitsu:123:2', seconds: 400),
      progress(type: 'anime', id: 'anilist:123:2', seconds: 500)]) {
      await history.save(p);
    }
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.entries.length, 5);
    expect(restored.position('series', 'tt123:1:3'), const Duration(seconds: 200));
    expect(restored.position('movie', 'tt123:1:2'), const Duration(seconds: 300));
    expect(restored.position('series', 'kitsu:123:2'), const Duration(seconds: 400));
    expect(restored.position('anime', 'anilist:123:2'), const Duration(seconds: 500));
    expect(restored.position('series', 'tt123:1:9'), Duration.zero);
  });

  test('the same identity updates progress across online and offline sources', () async {
    final history = ViewingHistory();
    await history.load();
    await history.save(progress());
    await history.save(progress(seconds: 450));
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.entries.length, 1);
    expect(restored.position('series', 'tt123:1:2'), const Duration(seconds: 450));
  });

  test('unscoped and unsupported addon IDs cannot share a resume position', () async {
    final history = ViewingHistory();
    await history.load();
    for (final id in ['', '123', 'episode-2', 'custom:123', 'https://host/video?token=secret']) {
      await history.save(progress(id: id));
      expect(history.position('series', id), Duration.zero);
    }
    expect(history.entries, isEmpty);
  });

  test('95 percent completion removes only that episode; a seek back restores it', () async {
    final history = ViewingHistory();
    await history.load();
    await history.save(progress());
    await history.save(progress(id: 'tt123:1:3'));
    await history.save(progress(seconds: 1139));
    expect(history.position('series', 'tt123:1:2'), const Duration(seconds: 1139));
    await history.save(progress(seconds: 1140));
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.position('series', 'tt123:1:2'), Duration.zero);
    expect(restored.entries.single.videoId, 'tt123:1:3');
    await restored.save(progress(seconds: 200));
    expect(restored.entries.first.videoId, 'tt123:1:2');
  });

  test('unknown duration retains progress; zero clears it and invalid updates preserve it', () async {
    final history = ViewingHistory();
    await history.load();
    await history.save(progress(duration: 0));
    await history.save(progress(seconds: -1));
    await history.save(progress(duration: -1));
    expect(history.position('series', 'tt123:1:2'), const Duration(seconds: 123));
    await history.save(progress(seconds: 0));
    expect(history.entries, isEmpty);
  });

  test('removal and clear survive restart', () async {
    final history = ViewingHistory();
    await history.load();
    await history.save(progress());
    await history.save(progress(id: 'tt123:1:3'));
    await history.remove('series', 'tt123:1:2');
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.entries.single.videoId, 'tt123:1:3');
    await restored.clear();
    await history.load();
    expect(history.entries, isEmpty);
  });

  test('removing an already absent entry rewrites storage for a retry', () async {
    final history = ViewingHistory();
    await history.load();
    await history.save(progress());
    await history.remove('series', 'tt123:1:2');
    // Model an earlier failed write leaving the old registry on disk.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('viewingHistory', jsonEncode([progress().toJson()]));
    await history.remove('series', 'tt123:1:2');
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.entries, isEmpty);
  });

  test('corrupt records do not discard valid records or prevent startup', () async {
    SharedPreferences.setMockInitialValues({'viewingHistory': jsonEncode([
      progress().toJson(), {}, null, {...progress().toJson(), 'position': -4},
      {...progress().toJson(), 'videoId': ''}, progress(seconds: 1200).toJson(),
    ])});
    final history = ViewingHistory();
    await history.load();
    expect(history.entries.length, 1);
    for (final value in ['broken JSON', '{}', 42]) {
      SharedPreferences.setMockInitialValues({'viewingHistory': value});
      await history.load();
      expect(history.entries, isEmpty);
    }
  });

  test('history retains the 100 most recently watched unfinished videos', () async {
    final history = ViewingHistory();
    await history.load();
    for (var i = 0; i < 100; i++) { await history.save(progress(id: 'tt$i')); }
    await history.save(progress(id: 'tt0', seconds: 300));
    await history.save(progress(id: 'tt100'));
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.entries.length, 100);
    expect(restored.position('series', 'tt1'), Duration.zero);
    expect(restored.position('series', 'tt0'), const Duration(seconds: 300));
    expect(restored.entries.first.videoId, 'tt100');
  });
}
