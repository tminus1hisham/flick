import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:flick/jellyfin.dart';
import 'package:flick/screens/player.dart';

// PlayerScreen can't be pumped headless: Player() needs libmpv, which
// `flutter test` doesn't have. These cover the decisions it delegates to.
void main() {
  final movie = Item({'Id': 'x', 'Name': 'Movie', 'Type': 'Movie'});

  test('downloaded Jellyfin titles keep the Jellyfin player', () {
    // detail.dart plays downloads as PlayerScreen(item:, source: local).
    expect(
      PlayerScreen(item: movie, source: '/local.mkv').addonPlayback,
      isFalse,
    );
    expect(PlayerScreen(item: movie).addonPlayback, isFalse);
    expect(
      PlayerScreen(
        item: movie,
        source: 'http://x/v.mkv',
        report: false,
      ).addonPlayback,
      isTrue,
    );
  });

  group('stoppedEarly', () {
    const d = Duration(minutes: 100);
    bool early({
      bool started = true,
      bool error = true,
      Duration position = const Duration(minutes: 40),
      Duration duration = d,
      Duration? buffer,
    }) => stoppedEarly(
      started: started,
      error: error,
      position: position,
      duration: duration,
      buffer: buffer ?? position,
    );

    test('a stop before playback started is a failure', () {
      expect(early(started: false, error: false), isTrue);
    });
    test('past 90% is the end of the video', () {
      expect(early(position: const Duration(minutes: 91)), isFalse);
    });
    test('an unknown duration is the end of the video', () {
      expect(early(duration: Duration.zero), isFalse);
    });
    test('early after a stream error with nothing buffered is a failure', () {
      expect(early(), isTrue);
    });
    test('early without a stream error is the end of the video', () {
      expect(early(error: false), isFalse);
    });
    test('early with data still buffered is not a failure', () {
      expect(early(buffer: const Duration(minutes: 45)), isFalse);
    });
  });

  test('embedded subtitles leave out files added by sub-add', () {
    final tracks = [
      SubtitleTrack.auto(),
      SubtitleTrack.no(),
      SubtitleTrack('1', 'English', 'eng'),
      SubtitleTrack('2', 'en.srt', 'eng'),
      SubtitleTrack.data('1\n00:00:01,000 --> 00:00:02,000\nHi'),
    ];
    expect(embeddedSubtitles(tracks, {'2'}).map((t) => t.id), ['1']);
  });

  group('addedSubtitle', () {
    final list = jsonEncode([
      {'id': 1, 'type': 'video'},
      {'id': 1, 'type': 'sub', 'external': false},
      {'id': 2, 'type': 'sub', 'external': true},
      {'id': 3, 'type': 'sub', 'external': true},
    ]);

    test('returns the newly selected external track', () {
      expect(addedSubtitle(list, '3', {'2'}), '3');
    });
    test(
      'a failed add leaves sid on an embedded track, Off or an earlier file',
      () {
        expect(addedSubtitle(list, '1', {}), isNull);
        expect(addedSubtitle(list, 'no', {}), isNull);
        expect(addedSubtitle(list, '2', {'2'}), isNull);
      },
    );
  });

  group('seekZone', () {
    int zone(double x, double y, Size s) =>
        seekZone(Offset(x, y), s, top: 64, bottom: 100);

    test('thirds of a landscape player', () {
      const s = Size(800, 360);
      expect(zone(100, 180, s), -1);
      expect(zone(400, 180, s), 0);
      expect(zone(700, 180, s), 1);
    });
    test('thirds of a portrait player', () {
      const s = Size(360, 640);
      expect(zone(60, 320, s), -1);
      expect(zone(180, 320, s), 0);
      expect(zone(300, 320, s), 1);
    });
    test('the top bar and the seek bar with the bottom bar never seek', () {
      const s = Size(800, 360);
      expect(zone(100, 40, s), 0);
      expect(zone(700, 40, s), 0);
      // 360 - 100: the seek bar starts here.
      expect(zone(100, 270, s), 0);
      expect(zone(700, 350, s), 0);
      expect(zone(100, 70, s), -1);
      expect(zone(700, 250, s), 1);
    });
  });

  group('nudgeTarget', () {
    const duration = Duration(minutes: 40);
    Duration at(int s, {int? pending, required int by}) => nudgeTarget(
      position: Duration(seconds: s),
      pending: pending == null ? null : Duration(seconds: pending),
      duration: duration,
      seconds: by,
    );

    test('moves from the position', () {
      expect(at(100, by: 10), const Duration(seconds: 110));
      expect(at(100, by: -10), const Duration(seconds: 90));
    });
    test('adds up from a seek still pending, not the stale position', () {
      expect(at(100, pending: 120, by: 10), const Duration(seconds: 130));
      expect(at(100, pending: 120, by: -10), const Duration(seconds: 110));
    });
    test('stays within the video', () {
      expect(at(5, by: -10), Duration.zero);
      expect(at(5, pending: 0, by: -10), Duration.zero);
      expect(at(2395, by: 10), duration);
    });
  });

  group('SeekTaps', () {
    const left = Offset(100, 180), right = Offset(700, 180);
    late SeekTaps taps;
    late Duration t;
    setUp(() {
      taps = SeekTaps();
      t = const Duration(seconds: 1);
    });
    // One tap of [held] ms at [p], [after] ms after the last one ended.
    int tap(
      Offset p, {
      int zone = 1,
      int burst = 0,
      int held = 50,
      int after = 100,
      int pointer = 1,
    }) {
      t += Duration(milliseconds: after);
      taps.down(pointer, p, t);
      t += Duration(milliseconds: held);
      return taps.up(pointer, p, t, zone: zone, burst: burst);
    }

    test('a single tap does nothing; a double tap seeks that way', () {
      expect(tap(right), 0);
      expect(tap(right), 1);
      expect(tap(left, zone: -1), 0);
      expect(tap(left, zone: -1), -1);
    });
    test('the second tap must come quickly, on the same side', () {
      expect(tap(right), 0);
      expect(tap(right, after: 400), 0);
      expect(tap(left, zone: -1), 0);
      expect(tap(right), 0);
    });
    test('the middle third never seeks', () {
      expect(tap(const Offset(400, 180), zone: 0), 0);
      expect(tap(const Offset(400, 180), zone: 0), 0);
    });
    test('while a burst is open every tap on its side counts', () {
      expect(tap(right, burst: 1), 1);
      expect(tap(right, burst: 1, after: 350), 1);
      expect(tap(left, zone: -1, burst: 1), 0);
    });
    test('a long press, a drag, a second finger or a cancel is no tap', () {
      expect(tap(right), 0);
      expect(tap(right, held: 600), 0);

      expect(tap(right), 0);
      t += const Duration(milliseconds: 100);
      taps.down(1, right, t);
      taps.move(1, right + const Offset(40, 0));
      t += const Duration(milliseconds: 50);
      expect(taps.up(1, right, t, zone: 1, burst: 0), 0);

      expect(tap(right), 0);
      t += const Duration(milliseconds: 100);
      taps.down(1, right, t);
      taps.down(2, left, t);
      t += const Duration(milliseconds: 50);
      expect(taps.up(2, left, t, zone: -1, burst: 0), 0);
      expect(taps.up(1, right, t, zone: 1, burst: 0), 0);

      expect(tap(right), 0);
      taps.down(1, right, t);
      taps.cancel(1);
      expect(tap(right), 0);
    });
  });
}
