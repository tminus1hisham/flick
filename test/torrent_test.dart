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
}
