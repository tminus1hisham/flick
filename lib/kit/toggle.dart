import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Controlled favourite / like toggle.
///
/// The caller owns persistence and optimistic state. [onPressed] answers whether the state changed;
/// haptics play only then.
class ToggleAction extends StatefulWidget {
  const ToggleAction({
    required this.on,
    required this.icon,
    required this.onIcon,
    required this.label,
    required this.onLabel,
    required this.onPressed,
    super.key,
  });

  final bool on;
  final IconData icon, onIcon;

  /// Spoken action while off and while on.
  final String label, onLabel;
  final Future<bool> Function()? onPressed;

  @override
  State<ToggleAction> createState() => _ToggleActionState();
}

class _ToggleActionState extends State<ToggleAction> {
  bool _down = false;

  Future<void> _activate() async {
    final turningOn = !widget.on;
    if (await widget.onPressed?.call() ?? false) {
      turningOn ? HapticFeedback.lightImpact() : HapticFeedback.selectionClick();
    }
  }

  @override
  void didUpdateWidget(covariant ToggleAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onPressed != null;
    final label = widget.on ? widget.onLabel : widget.label;
    final color = !enabled
        ? FlickTokens.textSecondary
        : widget.on
            ? FlickTokens.accent
            : FlickTokens.textPrimary;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      toggled: widget.on,
      label: label,
      onTap: enabled ? _activate : null,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: AnimatedScale(
          scale: _down && !reduceMotion ? 0.97 : 1,
          duration: reduceMotion ? Duration.zero : FlickTokens.stateDuration,
          curve: FlickTokens.curveIn,
          child: Material(
            color: FlickTokens.surface1,
            borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              excludeFromSemantics: true,
              onTap: enabled ? _activate : null,
              onHighlightChanged: (down) {
                if (_down != down) setState(() => _down = down);
              },
              child: SizedBox.square(
                dimension: FlickTokens.minTouchTarget,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : FlickTokens.stateDuration,
                    switchInCurve: FlickTokens.curveIn,
                    switchOutCurve: FlickTokens.curveOut,
                    transitionBuilder: (child, animation) {
                      final fade = FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                      if (reduceMotion) return fade;
                      return ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.9,
                          end: 1,
                        ).animate(animation),
                        child: fade,
                      );
                    },
                    child: Icon(
                      widget.on ? widget.onIcon : widget.icon,
                      key: ValueKey(widget.on),
                      color: color,
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
