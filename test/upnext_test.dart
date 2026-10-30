import 'package:flick/addons.dart';
import 'package:flick/playback.dart';
import 'package:flick/state.dart';
import 'package:flick/upnext.dart';
import 'package:flutter_test/flutter_test.dart';

Video _v(int season, int episode) =>
    (id: 'tt1:$season:$episode', title: 'E$episode', season: season, episode: episode, released: null, thumbnail: null);

AddonStream _s(String name, String? group) => (
      name: name,
      title: null,
      infoHash: 'ed0afbc1',
      fileIdx: null,
      url: null,
      externalUrl: null,
      trackers: const [],
      filename: null,
      headers: const {},
      subtitles: const [],
      videoSize: null,
      videoHash: null,
      bingeGroup: group,
    );

const _min = Duration(minutes: 1), _sec = Duration(seconds: 1);

UpNextView _view({Duration position = Duration.zero, bool dismissed = false, bool forced = false,
        bool autoplay = true, Duration counted = Duration.zero, bool resolving = false}) =>
    upNextView(position: position, duration: _min * 40, dismissed: dismissed, forced: forced, autoplay: autoplay,
        counted: counted, resolving: resolving);

/// Answers streams() from [result]: a list, or anything else thrown.
class _Addons extends Addons {
  _Addons(this.result);
  final Object result;
  @override
  Future<List<AddonStream>> streams(Addon a, String type, String videoId) async =>
      switch (result) { final List<AddonStream> l => l, final e => throw e };
}

final _addon = Addon({'id': 'org.test', 'name': 'Test', 'resources': const []}, 'https://example.invalid');
final Meta _series = (id: 'tt1', type: 'series', name: 'Show', poster: null, background: null, logo: null,
    description: null, releaseInfo: null, runtime: null, imdbRating: null, genres: const [], videos: [_v(1, 2)]);

void main() {
  group('nextVideo', () {
    final s1 = [_v(1, 1), _v(1, 2), _v(1, 3), _v(2, 1)];
    test('mid-season, season boundary, last and unknown', () {
      expect(nextVideo(s1, 'tt1:1:1')?.id, 'tt1:1:2');
      expect(nextVideo(s1, 'tt1:1:3')?.id, 'tt1:2:1');
      expect(nextVideo(s1, 'tt1:2:1'), isNull);
      expect(nextVideo(s1, 'tt1:9:9'), isNull);
    });
    test('never steps from a regular season into specials; specials step to specials', () {
      final withSpecials = [_v(0, 1), _v(0, 2), _v(1, 1)];
      // Season 0 sorts first, so S1E1 is last; listing specials after it must not change that.
      expect(nextVideo([_v(1, 1), _v(0, 1)], 'tt1:1:1'), isNull);
      expect(nextVideo(withSpecials, 'tt1:0:1')?.id, 'tt1:0:2');
    });
    test('sorts unsorted input without touching it', () {
      final shuffled = [_v(2, 1), _v(1, 2), _v(1, 1)];
      expect(nextVideo(shuffled, 'tt1:1:2')?.id, 'tt1:2:1');
      expect(shuffled.first.id, 'tt1:2:1');
    });
  });

  test('bingeMatch: first in the group, none, or no group', () {
    final streams = [_s('a', 'x'), _s('b', 'y'), _s('c', 'y')];
    expect(bingeMatch(streams, 'y')?.name, 'b');
    expect(bingeMatch(streams, 'z'), isNull);
    expect(bingeMatch([_s('a', null)], null), isNull);
  });

  test('upNextAt: plausible outro, else 30 s before the end, nothing for short clips', () {
    expect(upNextAt(_min * 40, outro: _min * 38), _min * 38);
    expect(upNextAt(_min * 40, outro: _min * 10), _min * 40 - _sec * 30, reason: 'outro before the halfway mark');
    expect(upNextAt(_min * 40, outro: _min * 40 - _sec * 2), _min * 40 - _sec * 30, reason: 'outro too late');
    expect(upNextAt(_min * 40), _min * 40 - _sec * 30);
    expect(upNextAt(_min * 3 - _sec), isNull);
    expect(upNextAt(Duration.zero), isNull);
  });

  group('upNextView', () {
    final at = _min * 40 - _sec * 30;
    test('shows from the trigger point unless dismissed; forced always shows', () {
      expect(_view(position: at - _sec).visible, isFalse);
      expect(_view(position: at).visible, isTrue);
      expect(_view(position: at, dismissed: true).visible, isFalse);
      final forced = _view(forced: true, dismissed: true);
      expect(forced.visible, isTrue);
      expect(forced.countdown, isNull);
    });
    test('countdown only with autoplay, while visible', () {
      expect(_view(position: at, autoplay: false).countdown, isNull);
      expect(_view(position: at - _sec, counted: _sec * 4).countdown, isNull);
      final v = _view(position: at, counted: _sec * 4);
      expect(v.countdown, closeTo(0.4, 1e-9));
      expect(v.secondsLeft, 6);
      final over = _view(position: at, counted: _sec * 12);
      expect(over.countdown, 1.0);
      expect(over.secondsLeft, 0);
      expect(_view(position: at, counted: const Duration(milliseconds: 3500)).secondsLeft, 7);
    });
    test('a commit in flight stays visible after a seek back', () {
      expect(_view(position: at - _min, resolving: true).visible, isTrue);
    });
  });

  group('resolveNext', () {
    final video = _v(1, 2);
    Future<AddonNext> resolve(Object result, {Addon? addon, String? group = 'g'}) {
      addons = _Addons(result);
      return resolveNext(addon ?? _addon, _series, video, group);
    }

    test('the same binge group plays on, with the next episode playback', () async {
      final r = await resolve([_s('other', 'h'), _s('same', 'g')]);
      expect(r, isA<NextStream>());
      r as NextStream;
      expect(r.stream.name, 'same');
      expect(r.addon, same(_addon));
      expect(r.playback.videoId, 'tt1:1:2');
    });
    test('no group, no match or a failed fetch: pick a stream', () async {
      expect(await resolve([_s('same', 'g')], group: null), isA<PickStream>());
      expect(await resolve([_s('other', 'h')]), isA<PickStream>());
      expect(await resolve(AddonException(AddonError.unreachable)), isA<PickStream>());
    });
  });
  test('countdownEligible: every condition can hold the countdown', () {
    bool e({bool visible = true, bool autoplay = true, bool committed = false, bool playing = true,
            bool buffering = false, bool panel = false}) =>
        countdownEligible(visible: visible, autoplay: autoplay, committed: committed, playing: playing,
            buffering: buffering, panel: panel);
    expect(e(), isTrue);
    expect(e(visible: false), isFalse);
    expect(e(autoplay: false), isFalse);
    expect(e(committed: true), isFalse);
    expect(e(playing: false), isFalse);
    expect(e(buffering: true), isFalse);
    expect(e(panel: true), isFalse);
  });

  test('onCompletion: failure, dismissed and Autoplay off never advance; an open panel defers', () {
    CompletionStep c({bool stoppedEarly = false, bool visible = true, bool autoplay = true, bool dismissed = false,
            bool panel = false}) =>
        onCompletion(stoppedEarly: stoppedEarly, visible: visible, autoplay: autoplay, dismissed: dismissed,
            panel: panel);
    expect(c(), CompletionStep.now);
    expect(c(panel: true), CompletionStep.defer);
    expect(c(stoppedEarly: true), CompletionStep.no);
    expect(c(stoppedEarly: true, panel: true), CompletionStep.no);
    expect(c(visible: false), CompletionStep.no);
    expect(c(dismissed: true), CompletionStep.no);
    expect(c(autoplay: false), CompletionStep.no);
  });
}
