import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state.dart';
import '../theme.dart';

extension FlickTvContext on BuildContext {
  /// Android TV: D-pad focus and the 10-foot layout ([FlickTv]).
  bool get tv => device.tv;
}

/// The keys a remote or keyboard activates with.
const _activateKeys = [
  LogicalKeyboardKey.select,
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.gameButtonA,
  LogicalKeyboardKey.space,
];

/// `MaterialApp.shortcuts` on TV: the defaults, but a held activation key activates once. Arrows still repeat.
Map<ShortcutActivator, Intent> get tvShortcuts => {
      for (final e in WidgetsApp.defaultShortcuts.entries)
        if (!(e.key.triggers?.any(_activateKeys.contains) ?? false)) e.key: e.value,
      for (final key in _activateKeys) SingleActivator(key, includeRepeats: false): const ActivateIntent(),
    };

/// The focus ring: a [FlickTv.ringWidth] stroke outside the painted box, past a [FlickTv.ringGap] gap the
/// background shows through. Use as a foreground painter; it has no animation.
class FocusRing extends CustomPainter {
  const FocusRing({this.radius = FlickTokens.artworkRadius});

  /// The corner radius of the box it surrounds.
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = FlickTv.ringGap, width = FlickTv.ringWidth;
    final box = Offset.zero & size;
    canvas.drawDRRect(
      RRect.fromRectAndRadius(box.inflate(gap + width), Radius.circular(radius + gap + width)),
      RRect.fromRectAndRadius(box.inflate(gap), Radius.circular(radius + gap)),
      Paint()..color = FlickTokens.textPrimary,
    );
  }

  @override
  bool shouldRepaint(FocusRing oldDelegate) => oldDelegate.radius != radius;
}

/// The single focus owner for a TV control: one focus node, Select / Enter → [onActivate], and the
/// [FocusRing] while it has focus in keyboard (traditional) highlight mode.
///
/// An `InkWell` or Material button inside must not take focus itself: give it `canRequestFocus: false`
/// (wrap Material buttons in `ExcludeFocus`), or use [FocusFrame.button].
class FocusFrame extends StatefulWidget {
  const FocusFrame({
    required this.child,
    this.onActivate,
    this.radius = FlickTokens.artworkRadius,
    this.lift = false,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// [child] with an ink press for touch; focus and the remote go through the frame.
  FocusFrame.button({
    required Widget child,
    required this.onActivate,
    this.radius = FlickTokens.controlRadius,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  })  : lift = false,
        child = Material(
          type: MaterialType.transparency,
          child: InkWell(
            canRequestFocus: false,
            excludeFromSemantics: true,
            borderRadius: BorderRadius.circular(radius),
            onTap: onActivate,
            child: child,
          ),
        );

  final Widget child;
  final VoidCallback? onActivate;
  final double radius;

  /// Posters and cards only: scale 1.03 with a soft shadow while focused. Never with reduced motion.
  final bool lift;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<FocusFrame> createState() => _FocusFrameState();
}

class _FocusFrameState extends State<FocusFrame> {
  bool _ring = false;

  @override
  Widget build(BuildContext context) {
    final onActivate = widget.onActivate;
    final lifted = _ring && widget.lift && !MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(widget.radius);
    return Semantics(
      container: widget.semanticLabel != null,
      button: onActivate != null,
      label: widget.semanticLabel,
      onTap: onActivate,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onShowFocusHighlight: (on) => setState(() => _ring = on),
        actions: {
          if (onActivate != null) ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => onActivate()),
        },
        child: AnimatedScale(
          scale: lifted ? FlickTv.lift : 1,
          duration: FlickTv.liftDuration,
          curve: FlickTokens.curveIn,
          child: CustomPaint(
            foregroundPainter: _ring ? FocusRing(radius: widget.radius) : null,
            child: AnimatedContainer(
              duration: FlickTv.liftDuration,
              curve: FlickTokens.curveIn,
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [if (lifted) FlickTv.liftShadow],
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The selected state on TV: the angled red bar from Flick's mark, left of a label or icon.
class SlashMarker extends StatelessWidget {
  const SlashMarker({super.key});

  static final _lean = FlickTv.slashHeight * math.tan(FlickTv.slashLean * math.pi / 180);

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(FlickTv.slashWidth + _lean, FlickTv.slashHeight),
        painter: const _SlashPainter(),
      );
}

class _SlashPainter extends CustomPainter {
  const _SlashPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const w = FlickTv.slashWidth;
    final h = size.height, lean = size.width - w;
    canvas.drawPath(
      Path()..addPolygon([Offset(0, h), Offset(w, h), Offset(size.width, 0), Offset(lean, 0)], true),
      Paint()..color = FlickTokens.activeMarker,
    );
  }

  @override
  bool shouldRepaint(_SlashPainter oldDelegate) => false;
}

/// The last focused item id per key (a rail tab, a row, a grid), so a screen can restore focus on re-entry.
class FocusMemory {
  final _ids = <String, Object?>{};

  void remember(String key, Object? id) => _ids[key] = id;

  Object? recall(String key) => _ids[key];
}
