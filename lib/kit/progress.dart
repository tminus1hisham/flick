import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart' show Skeleton;

/// Shared download track; unknown sizes use a static skeleton.
class FlickProgress extends StatelessWidget {
  const FlickProgress({super.key, required this.value, required this.color});

  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FlickTokens.grid),
          child: SizedBox(
            height: FlickTokens.grid,
            child: ColoredBox(
              color: FlickTokens.surface2,
              child: value == null ? const Skeleton(height: FlickTokens.grid) : TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: value!, end: value!),
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : FlickTokens.stateDuration,
                curve: FlickTokens.curveIn,
                builder: (context, current, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: current,
                    heightFactor: 1,
                    child: ColoredBox(color: color),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

