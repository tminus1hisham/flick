// Double-tap and ±10 s seek feedback over the player (design/seek.md, visual by Codex).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class SeekRipple extends StatefulWidget {
  const SeekRipple({required this.side, required this.seconds, super.key});

  /// -1 back (left edge), 1 forward (right edge), 0 hidden.
  final int side;

  /// Running total; ignored when side == 0.
  final int seconds;

  @override
  State<SeekRipple> createState() => _SeekRippleState();
}

class _SeekRippleState extends State<SeekRipple>
    with SingleTickerProviderStateMixin {
  late final AnimationController _visibility;
  late final CurvedAnimation _opacity;
  late int _side;
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _side = widget.side == 0 ? -1 : widget.side;
    _seconds = widget.side == 0 ? 0 : widget.seconds;
    _visibility = AnimationController(
      vsync: this,
      duration: FlickTokens.artworkFadeDuration,
      reverseDuration: FlickTokens.stateDuration,
    );
    _opacity = CurvedAnimation(
      parent: _visibility,
      curve: FlickTokens.curveIn,
      reverseCurve: FlickTokens.curveOut,
    );
    _visibility.addStatusListener(_onStatus);
    if (widget.side != 0) {
      _visibility.forward();
    }
  }

  @override
  void didUpdateWidget(covariant SeekRipple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.side == 0) {
      _visibility.reverse();
    } else if (widget.side != _side && _visibility.value > 0) {
      _visibility.reverse();
    } else {
      _side = widget.side;
      _seconds = widget.seconds;
      _visibility.forward();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || widget.side == 0) return;

    // Switch edges only when invisible; use the latest pending total.
    setState(() {
      _side = widget.side;
      _seconds = widget.seconds;
    });
    _visibility.forward();
  }

  @override
  void dispose() {
    _visibility.removeStatusListener(_onStatus);
    _opacity.dispose();
    _visibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _side < 0;
    final reduced = MediaQuery.disableAnimationsOf(context);

    return ExcludeSemantics(
      child: SizedBox.expand(
        child: ClipRect(
          child: FadeTransition(
            opacity: _opacity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final preferredRadius = (constraints.maxWidth / 3)
                    .clamp(FlickTokens.grid * 24, FlickTokens.grid * 36)
                    .toDouble();
                final radius = math.min(
                  preferredRadius,
                  math.min(constraints.maxWidth, constraints.maxHeight / 2),
                );

                return Align(
                  alignment:
                      left ? Alignment.centerLeft : Alignment.centerRight,
                  child: SizedBox(
                    key: ValueKey(_side),
                    width: radius,
                    height: radius * 2,
                    child: CustomPaint(
                      painter: _SeekGlowPainter(
                        left: left,
                        seconds: _seconds,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(FlickTokens.railGap),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedSwitcher(
                                  duration: FlickTokens.stateDuration,
                                  reverseDuration: FlickTokens.stateDuration,
                                  switchInCurve: FlickTokens.curveIn,
                                  switchOutCurve: FlickTokens.curveOut,
                                  transitionBuilder: (child, animation) {
                                    final fade = FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    );
                                    if (reduced) return fade;
                                    return AnimatedBuilder(
                                      animation: animation,
                                      child: fade,
                                      builder: (context, child) {
                                        return Transform.translate(
                                          offset: Offset(
                                            0,
                                            FlickTokens.grid *
                                                (1 - animation.value),
                                          ),
                                          child: child,
                                        );
                                      },
                                    );
                                  },
                                  child: Text(
                                    '$_seconds s',
                                    key: ValueKey(_seconds),
                                    // RobotoMono's wide space reads "10  s";
                                    // retain Manrope with tabular figures.
                                    style: FlickText.cardTitle.copyWith(
                                      fontSize: FlickTokens.grid * 5,
                                      color: FlickTokens.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: FlickTokens.grid),
                                // Icons.forward is a straight arrow; mirror
                                // replay so both sides are the same circle.
                                Transform.flip(
                                  flipX: !left,
                                  child: const Icon(
                                    Icons.replay,
                                    size: FlickTokens.grid * 5,
                                    color: FlickTokens.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekGlowPainter extends CustomPainter {
  const _SeekGlowPainter({required this.left, required this.seconds});

  static const _segments = 6;

  final bool left;
  final int seconds;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height / 2);
    if (radius <= FlickTokens.grid) return;

    final center = Offset(left ? 0 : size.width, size.height / 2);
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          FlickTokens.background,
          FlickTokens.background.withValues(alpha: 0.82),
          FlickTokens.background.withValues(alpha: 0.28),
          FlickTokens.background.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 0.68, 1],
      ).createShader(bounds);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawCircle(center, radius, glow);

    final stroke = FlickTokens.grid / 2;
    final rimRadius = radius - stroke / 2;
    final rim = Rect.fromCircle(center: center, radius: rimRadius);
    final gap = FlickTokens.grid / rimRadius;
    final sweep = (math.pi - gap * (_segments - 1)) / _segments;
    final direction = left ? 1.0 : -1.0;
    final lit = math.min(_segments, math.max(0, seconds ~/ 10));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    for (var index = 0; index < _segments; index++) {
      paint.color = index < lit
          ? FlickTokens.accent.withValues(
              alpha: index == lit - 1 ? 1 : 0.45,
            )
          : FlickTokens.outline.withValues(alpha: 0.45);
      canvas.drawArc(
        rim,
        -math.pi / 2 + direction * index * (sweep + gap),
        direction * sweep,
        false,
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SeekGlowPainter oldDelegate) {
    return oldDelegate.left != left || oldDelegate.seconds != seconds;
  }
}
