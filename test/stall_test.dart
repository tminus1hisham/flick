import 'package:flick/stall.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026);

  test('three stalls inside two minutes trigger', () {
    final d = StallDetector();
    expect(d.record(t0), isFalse);
    expect(d.record(t0.add(const Duration(seconds: 40))), isFalse);
    expect(d.record(t0.add(const Duration(seconds: 100))), isTrue);
  });

  test('spread-out stalls do not trigger', () {
    final d = StallDetector();
    expect(d.record(t0), isFalse);
    expect(d.record(t0.add(const Duration(minutes: 2, seconds: 10))), isFalse);
    expect(d.record(t0.add(const Duration(minutes: 4, seconds: 20))), isFalse);
  });

  test('reset clears history', () {
    final d = StallDetector()
      ..record(t0)
      ..record(t0)
      ..reset();
    expect(d.record(t0), isFalse);
  });

  group('PauseWait', () {
    Duration s(int n) => Duration(seconds: n);
    DateTime at(int sec, [int ms = 0]) => t0.add(Duration(seconds: sec, milliseconds: ms));

    // Stalls from [from] for [secs] seconds; returns whether it escalated.
    bool stall(PauseWait w, int from, int secs) {
      w.buffering(true, at(from));
      return w.buffering(false, at(from + secs));
    }

    test('two genuine stalls inside 60 s escalate once', () {
      final w = PauseWait()..position(s(10), at(0));
      expect(w.seconds, 3);
      expect(stall(w, 0, 3), isFalse);
      expect(stall(w, 40, 3), isTrue);
      expect(w.seconds, 8);
      expect(stall(w, 50, 3), isFalse); // already escalated
      expect(w.seconds, 8);
    });

    test('two stalls 61 s apart do not escalate', () {
      final w = PauseWait()..position(s(10), at(0));
      expect(stall(w, 0, 3), isFalse);
      expect(stall(w, 61, 3), isFalse);
      expect(w.seconds, 3);
    });

    test('a stall right after a seek jump does not count', () {
      final w = PauseWait()..position(s(10), at(0));
      expect(stall(w, 0, 3), isFalse);
      w.position(s(20), at(30));
      w.position(s(600), at(30, 500)); // seek
      w.buffering(true, at(31));
      expect(w.buffering(false, at(36)), isFalse);
      expect(w.seconds, 3);
    });

    test('a seek jump reported after buffering began does not count', () {
      final w = PauseWait()..position(s(10), at(0));
      expect(stall(w, 0, 3), isFalse);
      w.position(s(19), at(29));
      w.position(s(20), at(30)); // normal playback: no jump just before the stall
      w.buffering(true, at(31));
      w.position(s(600), at(31, 200));
      expect(w.buffering(false, at(36)), isFalse);
    });

    test('a stall of 2 s or less does not count', () {
      final w = PauseWait()..position(s(10), at(0));
      expect(stall(w, 0, 3), isFalse);
      expect(stall(w, 30, 2), isFalse);
      expect(w.seconds, 3);
    });

    test('buffering before playback starts does not count', () {
      final w = PauseWait();
      w.buffering(true, at(0));
      w.buffering(false, at(10));
      w.position(s(10), at(10));
      expect(stall(w, 20, 3), isFalse);
    });

    test('three genuine stalls inside 2 min set repeated; seeks and short stalls do not count', () {
      final w = PauseWait()..position(s(10), at(0));
      stall(w, 0, 3);
      stall(w, 20, 2); // short
      w.position(s(600), at(39, 500)); // seek
      stall(w, 40, 3);
      stall(w, 60, 3);
      expect(w.repeated, isFalse);
      stall(w, 100, 3); // escalated already; still counted
      expect(w.repeated, isTrue);
      expect(w.seconds, 8);
    });
  });

  group('bufferView', () {
    const ms = Duration(milliseconds: 1);
    BufferView view({
      bool started = true,
      bool buffering = true,
      Duration waited = const Duration(seconds: 1),
      double percent = 0,
      double? lastProgress,
      bool online = true,
      bool repeatedStalls = false,
      ({int peers, int rate, Duration age})? torrent,
    }) => bufferView(
          started: started,
          buffering: buffering,
          waited: waited,
          percent: percent,
          lastProgress: lastProgress,
          online: online,
          repeatedStalls: repeatedStalls,
          torrent: torrent,
        );

    test('a mid-play stall stays hidden before 600 ms', () {
      expect(view(waited: ms * 599).phase, BufferPhase.hidden);
      expect(view(waited: ms * 600).phase, BufferPhase.stalled);
      expect(view(buffering: false, waited: const Duration(seconds: 5)).phase, BufferPhase.hidden);
    });

    test('starting shows before the first frame whatever buffering says', () {
      expect(view(started: false, buffering: false, waited: Duration.zero).phase, BufferPhase.starting);
      expect(view(started: false, buffering: true, waited: Duration.zero).phase, BufferPhase.starting);
    });

    test('offline replaces only a visible phase', () {
      expect(view(started: false, online: false, waited: Duration.zero).phase, BufferPhase.offline);
      expect(view(online: false).phase, BufferPhase.offline);
      expect(view(online: false, waited: ms * 100).phase, BufferPhase.hidden);
      expect(view(online: false, buffering: false).phase, BufferPhase.hidden);
    });

    test('progress comes from percent, is kept offline and is null at 0', () {
      expect(view(percent: 40).progress, closeTo(.4, 1e-9));
      expect(view(percent: 0, lastProgress: .3).progress, isNull);
      expect(view(percent: 0).progress, isNull);
      expect(view(online: false, percent: 0, lastProgress: .3).progress, .3);
      expect(view(online: false, percent: 80, lastProgress: .3).progress, .3);
    });

    test('stats: null for direct sources and offline; stale rate dropped after 2 s', () {
      expect(view().stats, isNull);
      final fresh = (peers: 6, rate: 1 << 20, age: const Duration(seconds: 2));
      final stale = (peers: 6, rate: 1 << 20, age: const Duration(milliseconds: 2001));
      expect(view(torrent: fresh).stats, (peers: 6, rate: 1 << 20));
      expect(view(torrent: stale).stats, (peers: 6, rate: null));
      expect(view(torrent: fresh, online: false).stats, isNull);
    });

    test('offerSwitch at 15 s or after repeated stalls, never when hidden', () {
      expect(view(waited: const Duration(seconds: 14)).offerSwitch, isFalse);
      expect(view(waited: const Duration(seconds: 15)).offerSwitch, isTrue);
      expect(view(started: false, waited: const Duration(seconds: 15)).offerSwitch, isTrue);
      expect(view(repeatedStalls: true).offerSwitch, isTrue);
      expect(view(repeatedStalls: true, waited: ms * 100).offerSwitch, isFalse);
      expect(view(repeatedStalls: true, buffering: false, waited: const Duration(seconds: 20)).offerSwitch, isFalse);
    });
  });
}
