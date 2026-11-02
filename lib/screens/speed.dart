import 'package:flutter/material.dart';

import '../kit/focus.dart';
import '../theme.dart';

String speedLabel(double rate) =>
    '${rate == rate.roundToDouble() ? rate.toInt() : rate}×';

class SpeedPanel extends StatelessWidget {
  const SpeedPanel({required this.rate, super.key});

  final double rate;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(FlickTokens.pageGutter),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Playback speed', style: context.tv ? FlickTv.railHeading : FlickText.railHeading),
      const SizedBox(height: FlickTokens.railGap),
      FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var step = 1; step <= 16; step++)
              Semantics(
                selected: rate == step / 4,
                child: FocusFrame.button(
                  autofocus: rate == step / 4,
                  semanticLabel: speedLabel(step / 4),
                  onActivate: () => Navigator.pop(context, step / 4),
                  child: SizedBox(
                    width: context.tv ? 80 : 64,
                    height: 48,
                    child: Center(
                      child: Text(
                        speedLabel(step / 4),
                        style: (context.tv ? FlickTv.body : FlickText.button).copyWith(
                          fontWeight: rate == step / 4 ? FontWeight.bold : null,
                          decoration: rate == step / 4
                              ? TextDecoration.underline
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ]),
  );
}
