import 'package:flutter/material.dart';

import '../stall.dart';

/// Stub so the player wiring compiles; Codex's panel replaces this file.
class BufferingPanel extends StatelessWidget {
  const BufferingPanel({required this.view, required this.onSwitch, super.key});

  final BufferView view;
  final VoidCallback onSwitch;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
