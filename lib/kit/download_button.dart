import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A separate trailing action beside the stream row's play target.
///
/// null progress = idle; 0–1 = registered/downloading; done wins.
/// The owner supplies the action and owns registration and completion haptics.
class DownloadButton extends StatefulWidget {
  const DownloadButton({
    super.key,
    required this.progress,
    required this.done,
    required this.onPressed,
    this.label = 'Download',
  }) : assert(
          progress == null ||
              (progress >= 0 && progress <= 1),
        );

  final double? progress;
  final bool done;
  final VoidCallback? onPressed;
  final String label;

  @override
  State<DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<DownloadButton> {
  bool _down = false;

  @override
  void didUpdateWidget(covariant DownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? Duration.zero : FlickTokens.stateDuration;
    final enabled = widget.onPressed != null;
    final active = !widget.done && widget.progress != null;
    final state = widget.done ? 'done' : active ? 'progress' : 'idle';
    final spoken = widget.done
        ? 'Downloaded'
        : active
            ? 'Downloading'
            : widget.label;
    final value = widget.done
        ? '100 percent, ready offline'
        : active
            ? '${(widget.progress! * 100).floor()} percent'
            : null;
    final color = widget.done
        ? context.flick.success
        : active
            ? context.flick.progress
            : enabled
                ? FlickTokens.textPrimary
                : FlickTokens.textSecondary;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: spoken,
      value: value,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: spoken,
        excludeFromSemantics: true,
        child: AnimatedScale(
          scale: _down && !reduced ? 0.97 : 1,
          duration: duration,
          curve: FlickTokens.curveIn,
          child: Material(
            color: FlickTokens.surface1,
            borderRadius: BorderRadius.circular(
              FlickTokens.controlRadius,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              excludeFromSemantics: true,
              onTap: widget.onPressed,
              onHighlightChanged: (down) {
                if (_down != down) setState(() => _down = down);
              },
              child: SizedBox.square(
                dimension: FlickTokens.minTouchTarget,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: FlickTokens.curveIn,
                    switchOutCurve: FlickTokens.curveOut,
                    transitionBuilder: (child, animation) {
                      final fade = FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                      if (reduced) return fade;
                      return ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.9,
                          end: 1,
                        ).animate(animation),
                        child: fade,
                      );
                    },
                    child: SizedBox.square(
                      key: ValueKey(state),
                      dimension: FlickTokens.grid * 8,
                      child: active
                          ? TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: widget.progress!,
                                end: widget.progress!,
                              ),
                              duration: duration,
                              curve: FlickTokens.curveIn,
                              builder: (context, progress, _) => CustomPaint(
                                painter: _DownloadRing(
                                  progress: progress,
                                  color: color,
                                ),
                                child: Icon(
                                  Icons.south_rounded,
                                  size: FlickTokens.grid * 4,
                                  color: color,
                                ),
                              ),
                            )
                          : Icon(
                              widget.done
                                  ? Icons.check_rounded
                                  : Icons.file_download_outlined,
                              size: FlickTokens.grid * 6,
                              color: color,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadRing extends CustomPainter {
  const _DownloadRing({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = FlickTokens.grid / 2;
    final bounds = Offset.zero & size;
    final rect = bounds.deflate(stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = FlickTokens.outline;

    canvas.drawOval(rect, paint);
    if (progress <= 0) return;

    paint.color = color;
    if (progress >= 1) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DownloadRing oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
