/// Counts playback stalls in a sliding window.
/// ponytail: stall-count heuristic; add bandwidth measurement if it misfires.
class StallDetector {
  StallDetector({this.threshold = 3, this.window = const Duration(minutes: 2)});

  final int threshold;
  final Duration window;
  final _stalls = <DateTime>[];

  /// Records a stall at [t]; returns true when the window holds [threshold] stalls.
  bool record(DateTime t) {
    _stalls
      ..add(t)
      ..removeWhere((s) => t.difference(s) > window);
    return _stalls.length >= threshold;
  }

  void reset() => _stalls.clear();
}
