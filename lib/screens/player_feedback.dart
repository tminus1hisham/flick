import 'package:flutter/material.dart';

import '../kit/focus.dart';
import '../theme.dart';

/// Persistent feedback above the video, including media_kit's fullscreen route.
class PlayerFeedback extends StatelessWidget {
  const PlayerFeedback({super.key, required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => FocusScope(autofocus: context.tv, child: SafeArea(child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 76, 20, 76),
    child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Material(color: FlickTokens.surface2,
        borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
        child: SingleChildScrollView(padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: Semantics(liveRegion: true,
              child: Text(message, style: context.tv ? FlickTv.body : FlickText.body))),
            const SizedBox(width: 12),
            FocusFrame.button(autofocus: context.tv, semanticLabel: 'Dismiss message', onActivate: onDismiss,
              child: const SizedBox.square(dimension: 48, child: Icon(Icons.close))),
          ])),
      ),
    )),
  )));
}
