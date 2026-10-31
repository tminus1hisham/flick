import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'focus.dart';

typedef RailDestination = ({IconData icon, String label});

/// The TV side rail: Flick's mark, [destinations] from the top, [bottom] anchored at the bottom (its index is
/// `destinations.length`). A [FlickTv.railColumn] surface1 column that, while an item has focus, slides a
/// [FlickTv.railExpanded] panel with labels over the content; the column itself never changes width.
///
/// Focus entering the rail from outside lands on [selected]. Right calls [onRight]; Up and Down stay inside.
class FlickRail extends StatefulWidget {
  const FlickRail({
    required this.scope,
    required this.destinations,
    required this.bottom,
    required this.selected,
    required this.onSelect,
    required this.onRight,
    super.key,
  });

  /// Owned by the caller, so it can ask whether the rail has focus and move focus to it.
  final FocusScopeNode scope;
  final List<RailDestination> destinations;
  final RailDestination bottom;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onRight;

  @override
  State<FlickRail> createState() => _FlickRailState();
}

class _FlickRailState extends State<FlickRail> with SingleTickerProviderStateMixin {
  late final _t = AnimationController(vsync: this, duration: FlickTv.railIn, reverseDuration: FlickTv.railOut)
    ..addStatusListener((_) => setState(() {}));
  late final _curve = CurvedAnimation(parent: _t, curve: FlickTokens.curveIn, reverseCurve: FlickTokens.curveOut);
  final _nodes = <FocusNode>[];

  List<RailDestination> get _all => [...widget.destinations, widget.bottom];

  @override
  void dispose() {
    _curve.dispose();
    _t.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _focusChanged(bool focused) {
    // Entering from outside (Left from the content, Back at a tab root) always lands on the selected item.
    final selected = _nodes[widget.selected];
    if (focused && !selected.hasPrimaryFocus) selected.requestFocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      _t.value = focused ? 1 : 0;
    } else if (focused) {
      _t.forward();
    } else {
      _t.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    const target = FlickTokens.minTouchTarget, icon = target / 2, margin = (target - icon) / 2;
    // Targets centred in the column right of the inset; labels end a content gap inside the panel.
    const left = FlickTv.insetH + (FlickTv.railColumn - FlickTv.insetH - target) / 2;
    final open = !_t.isDismissed;
    final all = _all;
    while (_nodes.length < all.length) {
      _nodes.add(FocusNode(debugLabel: 'rail ${_nodes.length}'));
    }
    Widget item(int i) {
      final d = all[i];
      final on = i == widget.selected;
      final color = on ? FlickTokens.textPrimary : FlickTokens.textSecondary;
      return FocusFrame.button(
        focusNode: _nodes[i],
        semanticLabel: d.label,
        onActivate: () => widget.onSelect(i),
        child: SizedBox(
          height: target,
          width: open ? FlickTv.railExpanded - left - FlickTv.contentGap : target,
          child: Row(children: [
            SizedBox.square(
              dimension: target,
              child: Row(children: [
                // The selected slash sits in the target's left margin, inside the focus ring.
                SizedBox(width: margin, child: on ? const Center(child: SlashMarker()) : null),
                Icon(d.icon, size: icon, color: color),
              ]),
            ),
            if (open)
              Expanded(
                child: ExcludeSemantics(
                  child: FadeTransition(
                    opacity: _curve,
                    child: AnimatedBuilder(
                      animation: _curve,
                      builder: (_, child) =>
                          Transform.translate(offset: Offset(-FlickTokens.grid * 3 * (1 - _curve.value), 0), child: child),
                      child: Text(d.label, style: FlickTv.card.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
    }

    return FocusScope(
      node: widget.scope,
      onFocusChange: _focusChanged,
      child: Actions(
        actions: {
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(onInvoke: (intent) {
            if (intent.direction == TraversalDirection.right) {
              widget.onRight();
            } else {
              primaryFocus?.focusInDirection(intent.direction);
            }
            return null;
          }),
        },
        child: Stack(children: [
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: FlickTv.railColumn,
            child: ColoredBox(color: FlickTokens.surface1),
          ),
          if (open)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: FlickTv.railExpanded,
              // Slides out from behind the column's edge: translate only, never width.
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(-(FlickTv.railExpanded - FlickTv.railColumn) / FlickTv.railExpanded, 0),
                  end: Offset.zero,
                ).animate(_curve),
                child: const ColoredBox(key: ValueKey('rail-panel'), color: FlickTokens.surface1),
              ),
            ),
          // Keyed: the panel above is inserted only while open, and without a key the items would be matched
          // to its slot and rebuilt, so the focused item's FocusFrame would lose its state (and its ring).
          Positioned(
            key: const ValueKey('rail-items'),
            left: left,
            top: FlickTv.insetV,
            bottom: FlickTv.insetV,
            // Clipped to the sliding panel's right edge, so the focused item's ring (its width is already full)
            // never paints over the content beyond the panel while it slides in or out.
            child: AnimatedBuilder(
              animation: _curve,
              builder: (_, child) => ClipRect(
                clipper: _RailClip(lerpDouble(FlickTv.railColumn, FlickTv.railExpanded, _curve.value)! - left),
                child: child,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox.square(dimension: target, child: Center(child: FlickMark())),
              const SizedBox(height: FlickTokens.sectionGap),
              for (var i = 0; i < widget.destinations.length; i++) ...[
                if (i > 0) const SizedBox(height: FlickTokens.grid * 2),
                item(i),
              ],
              const Spacer(),
              item(widget.destinations.length),
            ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Everything left of [right], with room for a ring on the other three sides.
class _RailClip extends CustomClipper<Rect> {
  const _RailClip(this.right);
  final double right;

  @override
  Rect getClip(Size size) {
    const ring = FlickTv.ringGap + FlickTv.ringWidth;
    return Rect.fromLTRB(-ring, -ring, right, size.height + ring);
  }

  @override
  bool shouldReclip(_RailClip oldClipper) => oldClipper.right != right;
}
