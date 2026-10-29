import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:flick/screens/player.dart';

// PlayerScreen can't be pumped headless: Player() needs libmpv, which
// `flutter test` doesn't have. These cover the decisions it delegates to.
void main() {
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
}
