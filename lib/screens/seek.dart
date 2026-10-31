// Double-tap and ±10 s seek feedback over the player (design/seek.md, visual by Codex).
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
  late final AnimationController _pulse;
  late final CurvedAnimation _opacity;
  late int _side;
  late int _seconds;
  bool _reduced = false;

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
    _pulse = AnimationController(
      vsync: this,
      duration: FlickTokens.stateDuration,
      value: 1,
    );
    if (widget.side != 0) {
      _visibility.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _pulse.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant SeekRipple oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.side == 0) {
      _visibility.reverse();
      return;
    }

    // Retain the last visible side and total throughout the exit.
    _side = widget.side;
    _seconds = widget.seconds;
    _visibility.forward();
    if (oldWidget.side != widget.side ||
        oldWidget.seconds != widget.seconds) {
      if (_reduced) {
        _pulse.value = 1;
      } else {
        _pulse.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _visibility.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _side < 0;
    final alignment = left ? Alignment.centerLeft : Alignment.centerRight;

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
                final radius = preferredRadius
                    .clamp(0.0, constraints.maxHeight / 2)
                    .toDouble();
                final edge = Radius.circular(radius);

                return Align(
                  alignment: alignment,
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, child) {
                      if (_reduced) return child!;
                      final progress =
                          FlickTokens.curveIn.transform(_pulse.value);
                      return Transform.scale(
                        scale: 1 + (1 - progress) * 0.04,
                        alignment: alignment,
                        child: child,
                      );
                    },
                    child: SizedBox(
                      width: radius,
                      height: radius * 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: FlickTokens.background.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.horizontal(
                            left: left ? Radius.zero : edge,
                            right: left ? edge : Radius.zero,
                          ),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(
                              FlickTokens.grid * 2,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    left
                                        ? Icons.fast_rewind
                                        : Icons.fast_forward,
                                    size: FlickTokens.grid * 8,
                                    color: FlickTokens.textPrimary,
                                  ),
                                  const SizedBox(height: FlickTokens.grid),
                                  Text(
                                    '$_seconds s',
                                    style: monoStyle.copyWith(
                                      color: FlickTokens.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
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
