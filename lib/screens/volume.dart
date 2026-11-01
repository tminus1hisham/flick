import 'package:flutter/material.dart';

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
      return AlertDialog(
        title: const Text('Volume'),
        scrollable: true,
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${volume.round()}%'),
              Semantics(
                label: 'Volume',
                child: Slider(
                  autofocus: true,
                  value: volume,
                  max: 100,
                  divisions: 100,
                  semanticFormatterCallback: (value) => '${value.round()}%',
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: onMute,
            icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            label: Text(muted ? 'Unmute' : 'Mute'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
    },
  );
}
