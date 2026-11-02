import 'package:flutter/material.dart';

import '../theme.dart';

/// A modal route owns focus and Back even above media_kit's fullscreen route.
Future<T?> showPlaybackSidebar<T>(BuildContext context, WidgetBuilder builder) {
  final focus = FocusManager.instance.primaryFocus;
  final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : FlickTokens.sheetDuration;
  return Navigator.of(context).push<T>(PageRouteBuilder<T>(
    opaque: false, barrierDismissible: true, barrierLabel: 'Close playback queue',
    barrierColor: FlickTokens.background.withValues(alpha: 0.25),
    transitionDuration: duration, reverseTransitionDuration: duration,
    pageBuilder: (context, _, _) => Align(alignment: Alignment.centerRight,
      child: SizedBox(width: MediaQuery.sizeOf(context).width.clamp(0, 440).toDouble(),
        child: Material(color: FlickTokens.surface1.withValues(alpha: 0.94),
          child: SafeArea(child: builder(context))))),
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: animation, curve: FlickTokens.curveIn, reverseCurve: FlickTokens.curveOut)), child: child),
  )).whenComplete(() { if (focus?.context != null) focus!.requestFocus(); });
}
