import 'package:flutter/material.dart';

import '../theme.dart';
import 'focus.dart';

/// Couch-distance spacing and type for the utility screens; phone layout stays local.
class TvSurface extends StatelessWidget {
  const TvSurface({super.key, required this.child, this.title, this.back = false, this.action});
  final Widget child;
  final String? title;
  final bool back;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    if (!context.tv) return child;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(style: theme.textButtonTheme.style?.copyWith(
          textStyle: const WidgetStatePropertyAll(FlickTv.body))),
        filledButtonTheme: FilledButtonThemeData(style: theme.filledButtonTheme.style?.copyWith(
          textStyle: const WidgetStatePropertyAll(FlickTv.body))),
        outlinedButtonTheme: OutlinedButtonThemeData(style: theme.outlinedButtonTheme.style?.copyWith(
          textStyle: const WidgetStatePropertyAll(FlickTv.body))),
        textTheme: theme.textTheme.copyWith(
        titleMedium: FlickTv.railHeading, titleSmall: FlickTv.card,
        bodyMedium: FlickTv.body, labelMedium: FlickTv.meta,
      )),
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
        child: SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(FlickTv.insetH, FlickTv.insetV,
            FlickTv.insetH, FlickTv.insetV),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null) ...[
              Row(children: [
                if (back) ...[
                  FocusFrame.button(onActivate: () => Navigator.pop(context), semanticLabel: 'Back',
                    child: const SizedBox.square(dimension: 48, child: Icon(Icons.arrow_back))),
                  const SizedBox(width: FlickTv.contentGap),
                ],
                Expanded(child: Text(title!, style: FlickTv.page)),
                ?action,
              ]),
              const SizedBox(height: FlickTv.contentGap),
            ],
            Expanded(child: child),
          ]),
        )),
      ),
    );
  }
}

/// Give an existing Material control the TV ring without adding an activation owner.
class TvControl extends StatefulWidget {
  const TvControl({super.key, required this.child});
  final Widget child;

  @override
  State<TvControl> createState() => _TvControlState();
}

class _TvControlState extends State<TvControl> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_changed);
    FocusManager.instance.addHighlightModeListener(_changed);
  }

  void _changed([Object? _]) {
    final focused = FocusManager.instance.highlightMode == FocusHighlightMode.traditional &&
      FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<_TvControlState>() == this;
    if (mounted && focused != _focused) setState(() => _focused = focused);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_changed);
    FocusManager.instance.removeHighlightModeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.tv) return widget.child;
    return CustomPaint(foregroundPainter: _focused ? const FocusRing(radius: FlickTokens.controlRadius) : null,
      child: widget.child);
  }
}
