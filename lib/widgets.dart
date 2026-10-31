import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' show ClientException;

import 'theme.dart';

/// A sentence a viewer can act on, instead of an exception dump.
String friendlyError(Object e) => switch (e) {
      SocketException() || ClientException() || TimeoutException() =>
        "Can't reach this addon. Check your connection and try again.",
      _ => '$e',
    };

/// Network artwork that fades in, falling back to [fallback] and then to a quiet placeholder.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {this.fallback, this.icon = true, this.onError, super.key});
  final String url;
  final String? fallback;

  /// Told after the image (and any [fallback]) failed, for callers that drop the image instead of showing the tile.
  final VoidCallback? onError;

  /// Whether the placeholder shows a media icon; off where text sits on the artwork.
  final bool icon;

  @override
  Widget build(BuildContext context) => Image.network(
        url,
        fit: BoxFit.cover,
        frameBuilder: (_, child, frame, sync) => sync
            ? child
            : AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: child,
              ),
        errorBuilder: (context, _, _) {
          if (fallback != null) return NetImage(fallback!, icon: icon, onError: onError);
          final told = onError;
          if (told != null) WidgetsBinding.instance.addPostFrameCallback((_) => told());
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: icon
                ? Center(
                    child: Icon(Icons.movie_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  )
                : null,
          );
        },
      );
}

/// A rounded block standing in for content that is still loading.
class Skeleton extends StatelessWidget {
  const Skeleton({this.width, this.height, this.radius = 8, super.key});
  final double? width, height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Poster grid.
const posterGrid = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 130,
  childAspectRatio: 0.46,
  crossAxisSpacing: FlickTokens.railGap,
  mainAxisSpacing: 20,
);

/// Poster grid stand-in: artwork and a caption bar per cell, laid out by [delegate].
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({required this.padding, this.delegate = posterGrid, super.key});
  final EdgeInsetsGeometry padding;
  final SliverGridDelegate delegate;

  @override
  Widget build(BuildContext context) => GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: delegate,
        itemCount: 12,
        itemBuilder: (_, _) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 2 / 3, child: Skeleton(radius: FlickTokens.artworkRadius)),
          SizedBox(height: 8),
          Skeleton(width: 80, height: 12, radius: 4),
        ]),
      );
}

/// Takes over from the native splash: the mark sits exactly where Android drew
/// it while the app fades in underneath, then the mark fades away. 280 ms, no
/// waiting; the app is interactive from the first frame. Skipped under reduce
/// motion. Mounted once per engine start, so resuming the app never replays it.
class SplashHandoff extends StatefulWidget {
  const SplashHandoff({super.key, required this.child});

  final Widget child;

  /// Matches res/drawable/splash_mark.xml: Android 12's icon box without an
  /// icon background, drawn centred in the window.
  static const markSize = 288.0;
  static const duration = Duration(milliseconds: 280);

  @override
  State<SplashHandoff> createState() => _SplashHandoffState();
}

class _SplashHandoffState extends State<SplashHandoff> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: SplashHandoff.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() {});
    });
  late final _content = CurvedAnimation(parent: _c, curve: const Interval(0, 120 / 280, curve: FlickTokens.curveIn));
  late final _markOut = CurvedAnimation(parent: _c, curve: const Interval(120 / 280, 1, curve: FlickTokens.curveIn));
  late final _mark = ReverseAnimation(_markOut);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _content.dispose();
    _markOut.dispose();
    _c.dispose();
    super.dispose();
  }

  // The child keeps its slot when the mark leaves, so app state survives.
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: FlickTokens.background,
        child: Stack(fit: StackFit.expand, children: [
          FadeTransition(opacity: _content, child: widget.child),
          if (!_c.isCompleted)
            IgnorePointer(
              child: FadeTransition(
                opacity: _mark,
                child: const Center(child: FlickMark.master(size: SplashHandoff.markSize)),
              ),
            ),
        ]),
      );
}
