import 'package:flutter/material.dart';

import '../kit/focus.dart';
import '../kit/sheet.dart';
import '../playback.dart';
import '../player_keys.dart' show playerTime;
import '../state.dart';
import '../theme.dart';

/// Null means dismissed; choosing a mode never changes the saved checkpoint.
Future<bool?> chooseStartOver(BuildContext context, Playback playback) async {
  final position = history.position(playback.type, playback.videoId);
  if (position == Duration.zero) return false;
  return showFlickSheet<bool>(context, (context) => InitialFocus(
    child: SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.all(FlickTokens.pageGutter),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(playback.title, style: context.tv ? FlickTv.railHeading : FlickText.railHeading),
        if (playback.subtitle != null) Text(playback.subtitle!, style: context.tv ? FlickTv.meta : FlickText.metadata),
        const SizedBox(height: FlickTokens.railGap),
        for (final (over, label) in [(false, 'Resume · ${playerTime(position)}'), (true, 'Start over')])
          if (context.tv) FocusFrame.button(semanticLabel: label, autofocus: !over,
            onActivate: () => Navigator.pop(context, over),
            child: Padding(padding: const EdgeInsets.all(12), child: Text(label, style: FlickTv.body)))
          else TextButton(onPressed: () => Navigator.pop(context, over),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)), child: Text(label)),
      ]),
    )),
  ));
}
