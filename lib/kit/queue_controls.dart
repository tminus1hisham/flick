import 'package:flutter/material.dart';

import 'focus.dart';
import '../theme.dart';

/// Retain each Material control's single focus owner and add the house TV ring.
class QueueFocus extends StatefulWidget {
  const QueueFocus({required this.child, super.key});
  final Widget child;
  @override
  State<QueueFocus> createState() => _QueueFocusState();
}

class _QueueFocusState extends State<QueueFocus> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    if (!context.tv) return widget.child;
    return Focus(canRequestFocus: false, skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: CustomPaint(foregroundPainter: _focused ? FocusRing(radius: FlickTokens.controlRadius) : null,
        child: widget.child));
  }
}

class QueueTextButton extends StatelessWidget {
  const QueueTextButton({required this.onPressed, required this.child, this.style, super.key});
  final VoidCallback? onPressed;
  final Widget child;
  final ButtonStyle? style;
  @override
  Widget build(BuildContext context) => QueueFocus(child: TextButton(onPressed: onPressed, style: style, child: child));
}

class QueueIconButton extends StatelessWidget {
  const QueueIconButton({required this.onPressed, required this.icon, required this.tooltip,
    this.focusNode, this.autofocus = false, super.key});
  final VoidCallback? onPressed;
  final Widget icon;
  final String tooltip;
  final FocusNode? focusNode;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => QueueFocus(child: IconButton(onPressed: onPressed,
    icon: icon, tooltip: tooltip, focusNode: focusNode, autofocus: autofocus));
}
