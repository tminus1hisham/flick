import 'dart:convert';

import 'package:background_downloader/background_downloader.dart';
import 'package:flick/downloads.dart';
import 'package:flick/torrent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hex = 'dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c';
  const b32 = 'BWBFL3G4PSSV7MF36GASHWDQMLNR63I4';
  final v2 = '1220${'a' * 64}';

  test('accepts v1 hex, base32 and v2 hashes', () {
    expect(isMagnet('magnet:?xt=urn:btih:$hex'), isTrue);
    expect(isMagnet('magnet:?xt=urn:btih:${hex.toUpperCase()}&dn=x'), isTrue);
    expect(isMagnet('magnet:?xt=urn:btih:$b32'), isTrue);
    expect(isMagnet('magnet:?xt=urn:btih:${b32.toLowerCase()}'), isTrue);
    expect(isMagnet('magnet:?xt=urn:btmh:$v2'), isTrue);
  });

  test('accepts hybrid, repeated xt, percent-encoded and padded input', () {
    expect(isMagnet('magnet:?xt=urn:btih:$hex&xt=urn:btmh:$v2'), isTrue);
    expect(isMagnet('magnet:?xt=urn:sha1:abc&xt=urn:btih:$hex'), isTrue);
    expect(isMagnet('magnet:?xt=urn%3Abtih%3A$hex'), isTrue);
    expect(isMagnet('  magnet:?xt=urn:btih:$hex \n'), isTrue);
  });

  test('rejects malformed hashes', () {
    expect(isMagnet('magnet:?xt=urn:btih:${hex.substring(1)}'), isFalse);
    expect(isMagnet('magnet:?xt=urn:btih:${hex}0'), isFalse);
    expect(isMagnet('magnet:?xt=urn:btih:${b32.substring(1)}1'), isFalse); // 1 is not base32
    expect(isMagnet('magnet:?xt=urn:btmh:${v2.substring(2)}'), isFalse);
    expect(isMagnet('magnet:?xt=urn:btmh:1114${'a' * 64}'), isFalse);
  });

  test('rejects non-magnets', () {
    expect(isMagnet('magnet:?dn=no-hash'), isFalse);
    expect(isMagnet('https://example.com/?xt=urn:btih:$hex'), isFalse);
    expect(isMagnet('urn:btih:$hex'), isFalse);
    expect(isMagnet(''), isFalse);
    expect(isMagnet('%%%:not a uri'), isFalse);
  });

  test('isVideo goes by extension', () {
    expect(isVideo('Big Buck Bunny.mp4'), isTrue);
    expect(isVideo('Season 1/Show.S01E01.MKV'), isTrue);
    expect(isVideo('poster.jpg'), isFalse);
    expect(isVideo('README'), isFalse);
    expect(isVideo('mp4'), isFalse);
  });

  test('invalid percent-encoding is rejected, not thrown', () {
    expect(isMagnet('magnet:?xt=%FF'), isFalse);
    expect(isMagnet('magnet:?xt=urn:btih:$hex&dn=%FF'), isFalse);
  });

  test('guessFile recognises episode spellings and returns the file index', () {
    for (final marker in ['S04E02', 's4e2', '4x02', 'S04.E02', 'S004E002']) {
      expect(guessFile([
        (index: 7, name: 'Show.$marker.mkv', size: 10),
        (index: 2, name: 'Show.S04E03.mkv', size: 100),
        (index: 9, name: 'Show.S04E02.jpg', size: 1000),
      ], season: 4, episode: 2), (index: 7, sure: true));
    }
  });

  test('guessFile suggests the largest of ambiguous episode matches', () {
    expect(guessFile([
      (index: 8, name: 'Show.S04E02.mp4', size: 10),
      (index: 3, name: 'Show.4x02.mkv', size: 20),
      (index: 1, name: 'Show.S04E03.mkv', size: 100),
    ], season: 4, episode: 2), (index: 3, sure: false));
  });

  test('guessFile opens the sole video even without an episode match', () {
    final files = [
      (index: 9, name: 'poster.jpg', size: 100),
      (index: 4, name: 'movie.MKV', size: 10),
    ];
    expect(guessFile(files), (index: 4, sure: true));
    expect(guessFile(files, season: 4, episode: 2), (index: 4, sure: true));
  });

  test('guessFile suggests the largest video without episode information', () {
    expect(guessFile([
      (index: 5, name: 'short.mp4', size: 10),
      (index: 8, name: 'movie.mkv', size: 20),
      (index: 2, name: 'archive.zip', size: 100),
    ]), (index: 8, sure: false));
  });

  test('guessFile returns null without videos', () {
    expect(guessFile([]), (index: null, sure: false));
    expect(guessFile([(index: 3, name: 'poster.jpg', size: 10)]),
        (index: null, sure: false));
  });

  test('guessFile does not match part of a longer season or episode number', () {
    for (final marker in ['S04E021', 'S14E02', '14x02', '4x021']) {
      expect(guessFile([
        (index: 6, name: 'Show.$marker.mkv', size: 10),
        (index: 9, name: 'unmatched.mkv', size: 20),
      ], season: 4, episode: 2), (index: 9, sure: false));
    }
  });

  test('torrent progress uses selected file bytes and remains active until native completion', () {
    final p = TorrentProgress.fromStatus({
      'downloaded': 250, 'total': 1000, 'done': false, 'path': null, 'error': null,
    });
    expect(p.downloaded, 250);
    expect(p.total, 1000);
    expect(p.progress, 0.25);
    expect(p.done, isFalse);
    expect(p.active, isTrue);
    expect(p.path, isNull);

    final waitingForMove = TorrentProgress.fromStatus({
      'downloaded': 1000, 'total': 1000, 'done': false, 'path': null,
    });
    expect(waitingForMove.progress, 1);
    expect(waitingForMove.done, isFalse);
    expect(waitingForMove.active, isTrue);
  });

  test('native completion needs a complete selected file and a local path', () {
    final p = TorrentProgress.fromStatus({
      'downloaded': 1000, 'total': 1000, 'done': true, 'path': '/files/episode.mkv',
    });
    expect(p.progress, 1);
    expect(p.done, isTrue);
    expect(p.active, isFalse);
    expect(p.path, '/files/episode.mkv');

    for (final patch in <Map<String, Object?>>[
      {'downloaded': 999},
      {'path': null},
      {'path': ''},
      {'total': 0},
      {'error': 'Downloaded file is missing'},
    ]) {
      final incomplete = TorrentProgress.fromStatus({
        'downloaded': 1000, 'total': 1000, 'done': true, 'path': '/files/episode.mkv',
        ...patch,
      });
      expect(incomplete.done, isFalse, reason: '$patch');
      expect(incomplete.path, isNull, reason: '$patch');
    }
  });

  test('torrent progress handles unknown totals and clamps byte counts', () {
    final unknown = TorrentProgress.fromStatus({});
    expect(unknown.downloaded, 0);
    expect(unknown.total, 0);
    expect(unknown.progress, 0);
    expect(unknown.active, isTrue);

    final negative = TorrentProgress.fromStatus({'downloaded': -5, 'total': -1});
    expect(negative.downloaded, 0);
    expect(negative.total, 0);
    expect(negative.progress, 0);

    final excess = TorrentProgress.fromStatus({'downloaded': 1500, 'total': 1000});
    expect(excess.downloaded, 1000);
    expect(excess.progress, 1);
    expect(excess.done, isFalse);
  });

  test('torrent errors stop active polling and do not expose a playable path', () {
    final p = TorrentProgress.fromStatus({
      'downloaded': 1000, 'total': 1000, 'done': true,
      'path': '/files/episode.mkv', 'error': 'Disk full',
    });
    expect(p.error, 'Disk full');
    expect(p.done, isFalse);
    expect(p.active, isFalse);
    expect(p.path, isNull);
  });

  final metadata = StreamDownload(
    title: '星の旅 "Season 1"',
    poster: 'https://example.com/poster.jpg',
    playback: (
      title: '星の旅 "Season 1"',
      subtitle: 'S01E02 · Departure',
      logo: 'https://example.com/logo.png',
      poster: 'https://example.com/poster.jpg',
      type: 'series',
      videoId: 'tt123:1:2',
      season: 1,
      episode: 2,
      meta: null,
    ),
  );

  KeptTorrent kept({bool done = false}) => KeptTorrent(
    id: 7,
    infoHash: hex,
    magnet: 'magnet:?xt=urn:btih:$hex&tr=https%3A%2F%2Fexample.com%2Fannounce',
    file: 4,
    dir: '/files/downloads/torrents/$hex',
    titleJson: metadata.toMetaData(),
    name: 'Season 1/Show.S01E02.mkv',
    size: 1000,
    done: done,
  );

  test('kept torrent persistence JSON round trips identity and playback', () {
    for (final done in [false, true]) {
      final original = kept(done: done);
      final encoded = jsonEncode([original.toJson()]);
      final decoded = (jsonDecode(encoded) as List<dynamic>).single as Map<String, dynamic>;
      final restored = KeptTorrent.fromJson(decoded);
      expect(restored.toJson(), original.toJson());
      expect(restored.taskId, 'torrent-$hex-4');
      expect(isMagnet(restored.magnet), isTrue);

      final title = StreamDownload.fromMetaData(restored.titleJson)!;
      expect(title.title, metadata.title);
      expect(title.poster, metadata.poster);
      expect(title.playback, metadata.playback);
    }
  });

  test('torrent adapter maps waiting, progress, completion and failure to download rows', () {
    final r = TorrentDownload(kept());
    expect(r.taskId, 'torrent-$hex-4');
    expect(r.stream.playback.videoId, 'tt123:1:2');
    expect(r.status, TaskStatus.enqueued);
    expect(r.active, isTrue);
    expect(r.progress, 0);
    expect(r.expectedFileSize, 1000);

    r.info = TorrentProgress.fromStatus({'downloaded': 400, 'total': 1000});
    expect(r.status, TaskStatus.running);
    expect(r.progress, 0.4);
    expect(r.active, isTrue);

    r.info = TorrentProgress.fromStatus({
      'downloaded': 1000, 'total': 1000, 'done': true, 'path': '/files/episode.mkv',
    });
    expect(r.status, TaskStatus.complete);
    expect(r.progress, 1);
    expect(r.active, isFalse);

    r.info = TorrentProgress.fromStatus({
      'downloaded': 400, 'total': 1000, 'error': 'Disk full',
    });
    expect(r.status, TaskStatus.failed);
    expect(r.active, isFalse);
  });

  test('persisted completion waits for native file validation before offering playback', () {
    final r = TorrentDownload(kept(done: true));
    expect(r.status, TaskStatus.enqueued);
    expect(r.active, isTrue);
    expect(r.info?.path, isNull);
  });
}
