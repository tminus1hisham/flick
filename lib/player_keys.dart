import 'package:flutter/services.dart';

/// A TV remote changes meaning with the controls visible; panel arrows stay with its focus scope.
enum TvPlayerCommand { none, toggle, play, pause, backward, forward, show, hide, closeTracks, exit }

TvPlayerCommand tvPlayerKey(LogicalKeyboardKey key, {required bool bar, required bool panel, bool repeat = false}) {
  final back = key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;
  if (key == LogicalKeyboardKey.mediaPlayPause) return repeat ? TvPlayerCommand.none : TvPlayerCommand.toggle;
  if (key == LogicalKeyboardKey.mediaPlay) return repeat ? TvPlayerCommand.none : TvPlayerCommand.play;
  if (key == LogicalKeyboardKey.mediaPause) return repeat ? TvPlayerCommand.none : TvPlayerCommand.pause;
  if (panel) return back ? TvPlayerCommand.closeTracks : TvPlayerCommand.none;
  if (back) return bar ? TvPlayerCommand.hide : TvPlayerCommand.exit;
  if (bar) return key == LogicalKeyboardKey.arrowDown ? TvPlayerCommand.hide : TvPlayerCommand.none;
  if (key == LogicalKeyboardKey.arrowLeft) return TvPlayerCommand.backward;
  if (key == LogicalKeyboardKey.arrowRight) return TvPlayerCommand.forward;
  if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) return TvPlayerCommand.show;
  if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter || key == LogicalKeyboardKey.gameButtonA || key == LogicalKeyboardKey.space) {
    return repeat ? TvPlayerCommand.none : TvPlayerCommand.toggle;
  }
  return TvPlayerCommand.none;
}

/// Unknown duration cannot be sought; never seek to EOF, including on very short videos.
Duration? tvSeek(Duration position, Duration duration, {required bool forward, Duration held = Duration.zero}) {
  if (duration <= Duration.zero) return null;
  final step = held >= const Duration(seconds: 1) ? 30 : 10;
  final end = (duration - const Duration(seconds: 1)).inMilliseconds.clamp(0, duration.inMilliseconds);
  return Duration(milliseconds: (position.inMilliseconds + (forward ? step : -step) * 1000).clamp(0, end));
}

String playerTime(Duration value) {
  final seconds = value.inSeconds.clamp(0, 1 << 31);
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return seconds >= 3600 ? '${seconds ~/ 3600}:$minutes:$tail' : '${seconds ~/ 60}:$tail';
}
