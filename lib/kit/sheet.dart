import 'package:flutter/material.dart';

import '../theme.dart';

/// Draggable content must use a primary vertical scroll view to resize before scrolling.
Future<T?> showFlickSheet<T>(BuildContext context, WidgetBuilder builder, {bool draggable = false}) => showModalBottomSheet<T>(
      context: context,
      // Sized to the content: the default 9/16 cap clips a short sheet at 1.3× text on a 640dp phone.
      isScrollControlled: true,
      showDragHandle: !draggable,
      enableDrag: !draggable,
      useSafeArea: true,
      sheetAnimationStyle:
          MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : FlickTokens.sheetAnimationStyle,
      builder: draggable ? (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _DraggableSheet(builder: builder)) : builder,
    );

class _DraggableSheet extends StatefulWidget {
  const _DraggableSheet({required this.builder});
  final WidgetBuilder builder;
  @override
  State<_DraggableSheet> createState() => _DraggableSheetState();
}

class _DraggableSheetState extends State<_DraggableSheet> {
  final _controller = DraggableScrollableController();
  double _dragDistance = 0;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    // Equal min/max extents trap list drags when the keyboard leaves little room.
    final minimum = (240 / constraints.maxHeight).clamp(0.4, 0.95).toDouble();
    final initial = 0.65.clamp(minimum, 1.0).toDouble();
    final stops = {minimum, initial, 1.0}.toList();
    return DraggableScrollableSheet(
    controller: _controller, expand: false, initialChildSize: initial, minChildSize: minimum,
    maxChildSize: 1, snap: !MediaQuery.disableAnimationsOf(context), snapSizes: stops,
    snapAnimationDuration: FlickTokens.sheetDuration, shouldCloseOnMinExtent: false,
    builder: (context, scroll) => Column(children: [
      Semantics(label: 'Resize playback queue', hint: 'Drag up to expand or down to close',
        onIncrease: () => _resize(1), onDecrease: () => _resize(minimum),
        child: GestureDetector(behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _dragDistance = 0,
          onVerticalDragUpdate: (details) {
            _dragDistance += details.delta.dy;
            _controller.jumpTo((_controller.size - details.delta.dy / constraints.maxHeight).clamp(minimum, 1.0));
          },
          onVerticalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (_controller.size <= minimum + 0.02 && _dragDistance > 0) {
              Navigator.pop(context);
              return;
            }
            final targets = velocity.abs() > 400
              ? stops.where((stop) => velocity < 0 ? stop > _controller.size : stop < _controller.size).toList()
              : stops.toList();
            targets.sort((a, b) => (a - _controller.size).abs().compareTo((b - _controller.size).abs()));
            _resize(targets.firstOrNull ?? _controller.size);
          },
          child: SizedBox(height: FlickTokens.minTouchTarget, width: double.infinity,
            child: Center(child: Container(width: 32, height: 4,
              decoration: BoxDecoration(color: FlickTokens.textSecondary,
                borderRadius: BorderRadius.circular(FlickTokens.grid))))))),
      Expanded(child: PrimaryScrollController(controller: scroll, child: widget.builder(context))),
    ]),
  );
  });

  void _resize(double size) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpTo(size);
    } else {
      _controller.animateTo(size, duration: FlickTokens.sheetDuration, curve: FlickTokens.curveIn);
    }
  }
}
