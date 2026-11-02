import 'package:flutter/material.dart';

import '../kit/tv_surface.dart';
import '../kit/focus.dart';
import '../theme.dart';

class VolumePanel extends StatelessWidget {
  const VolumePanel({
    required this.stream,
    required this.readVolume,
    required this.onChanged,
    required this.onMute,
    super.key,
  });

  final Stream<double> stream;
  final double Function() readVolume;
  final ValueChanged<double> onChanged;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
    stream: stream,
    builder: (context, _) {
      // Read current state even when reopened before another stream event.
      final volume = readVolume().clamp(0.0, 100.0);
      final muted = volume == 0;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(FlickTokens.pageGutter),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Volume', style: context.tv ? FlickTv.railHeading : FlickText.railHeading),
              const SizedBox(height: FlickTokens.railGap),
              Text('${volume.round()}%', style: context.tv ? FlickTv.body : FlickText.body),
              Semantics(
                label: 'Volume',
                child: TvControl(child: Slider(
                  autofocus: true,
                  value: volume,
                  max: 100,
                  divisions: 100,
                  semanticFormatterCallback: (value) => '${value.round()}%',
                  onChanged: onChanged,
                )),
              ),
              Wrap(spacing: FlickTokens.railGap, children: [
                TvControl(child: TextButton.icon(
                  onPressed: onMute,
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  label: Text(muted ? 'Unmute' : 'Mute'),
                )),
                TvControl(child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                )),
              ]),
            ],
          ),
        ),
      );
    },
  );
}
