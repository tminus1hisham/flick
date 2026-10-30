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

/// Addon playback's mpv `cache-pause-wait`: short until playback keeps
/// stalling, then long, so each stall rebuilds a real buffer. Rises once.
class PauseWait {
  PauseWait({this.initial = 3, this.escalated = 8});

  /// Seconds of cache mpv waits for after a stall.
  final int initial, escalated;
  final _stalls = StallDetector(threshold: 2, window: const Duration(seconds: 60));
  final _genuine = StallDetector();
  bool _escalated = false, _repeated = false;
  Duration? _position; // null until playback has started
  DateTime? _jump, _since;
  bool _seek = false;

  int get seconds => _escalated ? escalated : initial;

  /// True once 3 genuine stalls have fallen inside 2 minutes; stays true.
  bool get repeated => _repeated;

  /// Records a position report; a jump of more than 5 s is a seek.
  void position(Duration p, DateTime t) {
    final last = _position;
    _position = p;
    if (last == null || (p - last).abs() <= const Duration(seconds: 5)) return;
    _jump = t;
    if (_since != null) _seek = true; // the jump arrived after its buffering began
  }

  /// Records a buffering change; returns true once, when [seconds] has just risen.
  bool buffering(bool on, DateTime t) {
    if (on) {
      if (_position == null || _since != null) return false;
      final jump = _jump;
      _since = t;
      _seek = jump != null && !t.difference(jump).isNegative && t.difference(jump) <= const Duration(seconds: 1);
      return false;
    }
    final since = _since;
    _since = null;
    if (since == null || _seek) return false;
    if (t.difference(since) <= const Duration(seconds: 2)) return false;
    if (_genuine.record(since)) _repeated = true;
    if (_escalated) return false;
    return _escalated = _stalls.record(since);
  }
}

enum BufferPhase { hidden, starting, stalled, offline }

typedef BufferView = ({
  BufferPhase phase,
  double? progress, // 0..1 toward resuming in this episode; null = unknown
  ({int peers, int? rate})? stats, // torrent only; null = hide the line; rate null = not fresh
  bool offerSwitch, // show "Try another source"
});

/// What the addon player's buffering panel shows (design/buffering.md, Contract).
BufferView bufferView({
  required bool started,
  required bool buffering,
  required Duration waited,
  required double percent,
  required double? lastProgress,
  required bool online,
  required bool repeatedStalls,
  ({int peers, int rate, Duration age})? torrent,
}) {
  final visible = !started || (buffering && waited >= const Duration(milliseconds: 600));
  final phase = !visible
      ? BufferPhase.hidden
      : !online
          ? BufferPhase.offline
          : started
              ? BufferPhase.stalled
              : BufferPhase.starting;
  final offline = phase == BufferPhase.offline;
  return (
    phase: phase,
    progress: offline ? lastProgress : percent > 0 ? (percent / 100).clamp(0.0, 1.0) : null,
    stats: torrent == null || offline
        ? null
        : (peers: torrent.peers, rate: torrent.age > const Duration(seconds: 2) ? null : torrent.rate),
    offerSwitch: visible && (waited >= const Duration(seconds: 15) || repeatedStalls),
  );
}
