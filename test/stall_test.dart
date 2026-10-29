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
      w.position(s(20), at(30));
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
  });
}
