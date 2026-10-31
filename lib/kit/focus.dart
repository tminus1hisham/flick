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

/// Marks [child]'s focusables as the initial target of the enclosing tab or screen scope: [enterScope] lands
/// on the first of them when the scope has nothing remembered.
class InitialFocus extends StatelessWidget {
  const InitialFocus({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

bool _isText(FocusNode n) => n.context?.findAncestorWidgetOfExactType<EditableText>() != null;

/// Focus into [scope]: its remembered item, else the first focusable under an [InitialFocus], else its first
/// focusable. Never a text field: entering must not open the on-screen keyboard. With none, focus stays put.
void enterScope(FocusScopeNode scope) {
  final nodes = [for (final n in scope.traversalDescendants) if (n is! FocusScopeNode && !_isText(n)) n];
  final remembered = scope.focusedChild;
  final target = remembered != null && !_isText(remembered)
      ? remembered
      : nodes.where((n) => n.context?.findAncestorWidgetOfExactType<InitialFocus>() != null).firstOrNull ??
          nodes.firstOrNull;
  target?.requestFocus();
}

/// True while the key being handled is an auto-repeat (a held arrow), so moves jump instead of animating.
bool get keyRepeating => _repeat.on;
final _repeat = _RepeatWatch();

class _RepeatWatch {
  _RepeatWatch() {
    HardwareKeyboard.instance.addHandler((event) {
      on = event is KeyRepeatEvent;
      return false;
    });
  }
  bool on = false;
}

/// Marks what [tvReveal] scrolls into view for a focusable inside it, such as a poster with its title and
/// year below.
class RevealArea extends InheritedWidget {
  const RevealArea({required super.child, super.key});

  @override
  bool updateShouldNotify(RevealArea oldWidget) => false;
}

/// The TV [FocusTraversalPolicy.requestFocusCallback]: focus [node], then scroll it (or its [RevealArea]) into
/// view with [FlickTv.gridPad] beside it and the [FlickTv.insetV] safe area above and below, so the ring, the
/// lift and the labels are never clipped. [FlickTv.scrollDuration], or a jump while a key repeats or with
/// reduced motion.
void tvReveal(FocusNode node,
    {ScrollPositionAlignmentPolicy? alignmentPolicy, double? alignment, Duration? duration, Curve? curve}) {
  node.requestFocus();
  final context = node.context;
  if (context == null) return;
  final area = context.getElementForInheritedWidgetOfExactType<RevealArea>()?.findRenderObject();
  final box = area ?? context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return;
  final still = keyRepeating || MediaQuery.disableAnimationsOf(context);
  box.showOnScreen(
    rect: const EdgeInsets.symmetric(horizontal: FlickTv.gridPad, vertical: FlickTv.insetV)
        .inflateRect(Offset.zero & box.size),
    duration: still ? Duration.zero : FlickTv.scrollDuration,
    curve: FlickTokens.curveIn,
  );
}
