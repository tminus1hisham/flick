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
    with TickerProviderStateMixin {
  late final AnimationController _visibility;
  late final CurvedAnimation _opacity;
  // Lights the newest rim segment; a colour change, so reduced motion keeps it.
  late final AnimationController _step = AnimationController(
    vsync: this,
    duration: FlickTokens.stateDuration,
    value: 1,
  );
  late final CurvedAnimation _lit = CurvedAnimation(
    parent: _step,
    curve: FlickTokens.curveIn,
  );
  late int _side;
  late int _seconds;
  // A new burst after a fade-out starts a fresh label, so the last burst's
  // total doesn't cross-fade out under it (QA critic round 3).
  int _burst = 0;

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
    if (_visibility.isDismissed && widget.side != 0) _burst++;
    if (widget.side == 0) {
      _visibility.reverse();
    } else if (widget.side != _side && _visibility.value > 0) {
      _visibility.reverse();
    } else {
      if (widget.seconds > _seconds && widget.side == _side) {
        _step.forward(from: 0);
      }
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
    _lit.dispose();
    _step.dispose();
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
                    key: ValueKey((_side, _burst)),
                    width: radius,
                    height: radius * 2,
                    child: CustomPaint(
                      painter: _SeekGlowPainter(
                        left: left,
                        seconds: _seconds,
                        step: _lit,
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
  _SeekGlowPainter({
    required this.left,
    required this.seconds,
    required this.step,
  }) : super(repaint: step);

  static const _segments = 6;

  final bool left;
  final int seconds;

  /// 0 → 1 as the newest segment lights and the previous one dims.
  final Animation<double> step;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height / 2);
    if (radius <= FlickTokens.grid) return;

    final center = Offset(left ? 0 : size.width, size.height / 2);
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final glow = Paint()
      // A plateau under the whole label (out to 0.75 r at 1.3× text), so it
      // holds ≥ 5.4:1 (text, 1.3×) and 6:1 (icon) over a white frame
      // (design/seek.md); no solid black at the edge.
      ..shader = RadialGradient(
        colors: [
          FlickTokens.background.withValues(alpha: 0.88),
          FlickTokens.background.withValues(alpha: 0.8),
          FlickTokens.background.withValues(alpha: 0.3),
          FlickTokens.background.withValues(alpha: 0),
        ],
        stops: const [0, 0.78, 0.92, 1],
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

    final off = FlickTokens.outline.withValues(alpha: 0.45);
    final dim = FlickTokens.accent.withValues(alpha: 0.45);
    final t = step.value;
    for (var index = 0; index < _segments; index++) {
      paint.color = index >= lit
          ? off
          : index == lit - 1
          ? Color.lerp(off, FlickTokens.accent, t)!
          : index == lit - 2
          ? Color.lerp(FlickTokens.accent, dim, t)!
          : dim;
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
    return oldDelegate.left != left ||
        oldDelegate.seconds != seconds ||
        oldDelegate.step != step;
  }
}
