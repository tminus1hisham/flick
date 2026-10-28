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

  test('invalid percent-encoding is rejected, not thrown', () {
    expect(isMagnet('magnet:?xt=%FF'), isFalse);
    expect(isMagnet('magnet:?xt=urn:btih:$hex&dn=%FF'), isFalse);
  });
}
