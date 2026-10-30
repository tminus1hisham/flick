import 'package:flutter/material.dart';

import '../theme.dart';

/// The route an episode's screens (torrent start, player) open on. It enters like any page; with [next] (Up Next
/// moving on) it fades in over the background instead, so the stream list behind never shows. [popForNext] makes it
/// leave without its exit animation for the same reason.
class EpisodeRoute<T> extends MaterialPageRoute<T> {
  EpisodeRoute({required super.builder, this.next = false});

  final bool next;

  bool _leaving = false;

  /// The next pop skips the exit animation (the pop re-reads [reverseTransitionDuration]).
  void leaveNow() => _leaving = true;

  @override
  Duration get transitionDuration => next ? FlickTokens.artworkFadeDuration : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _leaving ? Duration.zero : super.reverseTransitionDuration;

  @override
  Widget buildTransitions(
      BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (!next) return super.buildTransitions(context, animation, secondaryAnimation, child);
    return AnimatedBuilder(
      animation: animation,
      // Opaque while entering; a plain fade back to the stream list on Back.
      builder: (_, child) => ColoredBox(
        color: animation.status == AnimationStatus.reverse
            ? FlickTokens.background.withValues(alpha: 0)
            : FlickTokens.background,
        child: child,
      ),
      child: FadeTransition(opacity: CurvedAnimation(parent: animation, curve: FlickTokens.curveIn), child: child),
    );
  }
}

/// Pops the current route with [result] at once when it is an [EpisodeRoute]: the next episode replaces it.
void popForNext(BuildContext context, Object? result) {
  final route = ModalRoute.of(context);
  if (route is EpisodeRoute) route.leaveNow();
  Navigator.pop(context, result);
}
