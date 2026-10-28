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
}
