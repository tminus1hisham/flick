import 'package:flutter/material.dart';

import 'package:flick/stall.dart';
import 'package:flick/theme.dart';
import 'package:flick/torrent.dart';

/// Playback status with a pass-through surface and an optional source action.
class BufferingPanel extends StatefulWidget {
  const BufferingPanel({required this.view, required this.onSwitch, super.key});

  final BufferView view;
  final VoidCallback onSwitch;

  @override
  State<BufferingPanel> createState() => _BufferingPanelState();
}

class _BufferingPanelState extends State<BufferingPanel> {
  BufferView? _lastVisible;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BufferingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final visible = widget.view.phase != BufferPhase.hidden;
    if (!visible) {
      _shown = false;
      return;
    }
    final appearing = _lastVisible == null;
    _lastVisible = widget.view;
    if (!appearing) {
      _shown = true;
      return;
    }
    // Mount at opacity 0, then fade in on the next frame.
    _shown = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.view.phase != BufferPhase.hidden) {
        setState(() => _shown = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = _lastVisible;
    if (view == null) return const SizedBox.shrink();

    final visible = widget.view.phase != BufferPhase.hidden;
    final offered = visible && widget.view.offerSwitch;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final enter = reducedMotion ? Duration.zero : FlickTokens.artworkFadeDuration;
    final exit = reducedMotion ? Duration.zero : FlickTokens.stateDuration;

    return Center(
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          opacity: _shown ? 1 : 0,
          duration: _shown ? enter : exit,
          curve: _shown ? FlickTokens.curveIn : FlickTokens.curveOut,
          onEnd: () {
            if (mounted && widget.view.phase == BufferPhase.hidden) {
              setState(() => _lastVisible = null);
            }
          },
          child: SizedBox(
            width: FlickTokens.grid * 80,
            child: Stack(
              children: [
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: FlickTokens.surface1,
                      borderRadius: BorderRadius.circular(FlickTokens.modalRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(FlickTokens.grid * 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PhaseText(view.phase, enter: enter, exit: exit),
                          const SizedBox(height: FlickTokens.grid * 4),
                          _BufferRail(
                            progress: view.progress,
                            offline: view.phase == BufferPhase.offline,
                          ),
                          if (view.stats != null && view.phase != BufferPhase.offline) ...[
                            const SizedBox(height: FlickTokens.railGap),
                            _BufferStats(view.stats!),
                          ],
                          const SizedBox(height: FlickTokens.grid * 4),
                          const SizedBox(height: FlickTokens.minTouchTarget),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: FlickTokens.grid * 6,
                  right: FlickTokens.grid * 6,
                  bottom: FlickTokens.grid * 6,
                  height: FlickTokens.minTouchTarget,
                  child: IgnorePointer(
                    ignoring: !offered,
                    child: ExcludeSemantics(
                      excluding: !offered,
                      child: ExcludeFocus(
                        excluding: !offered,
                        child: AnimatedSwitcher(
                          duration: enter,
                          reverseDuration: exit,
                          switchInCurve: FlickTokens.curveIn,
                          switchOutCurve: FlickTokens.curveOut,
                          child: offered
                              ? SizedBox.expand(
                                  key: const ValueKey('action'),
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: OutlinedButton(
                                      onPressed: widget.onSwitch,
                                      child: const Text('Try another source'),
                                    ),
                                  ),
                                )
                              : const SizedBox.expand(key: ValueKey('empty')),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhaseText extends StatelessWidget {
  const _PhaseText(this.phase, {required this.enter, required this.exit});

  final BufferPhase phase;
  final Duration enter;
  final Duration exit;

  @override
  Widget build(BuildContext context) {
    final title = switch (phase) {
      BufferPhase.starting => 'Starting playback',
      BufferPhase.stalled => 'Buffering',
      BufferPhase.offline => 'Waiting for connection',
      BufferPhase.hidden => '',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label: title,
          excludeSemantics: true,
          child: AnimatedSwitcher(
            duration: enter,
            reverseDuration: exit,
            switchInCurve: FlickTokens.curveIn,
            switchOutCurve: FlickTokens.curveOut,
            child: Text(
              title,
              key: ValueKey(phase),
              textAlign: TextAlign.center,
              style: FlickText.railHeading.copyWith(color: FlickTokens.textPrimary),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: enter,
          reverseDuration: exit,
          switchInCurve: FlickTokens.curveIn,
          switchOutCurve: FlickTokens.curveOut,
          child: phase == BufferPhase.offline
              ? Padding(
                  key: const ValueKey('offline'),
                  padding: const EdgeInsets.only(top: FlickTokens.grid * 2),
                  child: Text(
                    'Playback will resume automatically.',
                    textAlign: TextAlign.center,
                    style: FlickText.body.copyWith(color: FlickTokens.textSecondary),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('online')),
        ),
      ],
    );
  }
}

class _BufferRail extends StatelessWidget {
  const _BufferRail({required this.progress, required this.offline});

  final double? progress;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final value = progress;

    return ExcludeSemantics(
      child: Opacity(
        opacity: offline ? 0.4 : 1,
        child: SizedBox(
          height: FlickTokens.grid,
          child: value == null
              ? Row(
                  children: [
                    for (var index = 0; index < 6; index++) ...[
                      if (index > 0) const SizedBox(width: FlickTokens.grid),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: FlickTokens.surface2,
                            borderRadius: BorderRadius.circular(FlickTokens.grid),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  ],
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(FlickTokens.grid),
                  child: ColoredBox(
                    color: FlickTokens.surface2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: value.clamp(0.0, 1.0).toDouble(),
                        heightFactor: 1,
                        child: const ColoredBox(color: FlickTokens.progress),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _BufferStats extends StatelessWidget {
  const _BufferStats(this.stats);

  final ({int peers, int? rate}) stats;

  @override
  Widget build(BuildContext context) {
    final numberStyle = monoStyle.copyWith(
      fontSize: FlickText.metadata.fontSize,
      height: FlickText.metadata.height,
      color: FlickTokens.textSecondary,
    );
    final rate = stats.rate;
    final formattedRate = rate == null ? null : formatRate(rate);
    final separator = formattedRate?.indexOf(' ') ?? -1;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${stats.peers}', style: numberStyle),
          TextSpan(text: stats.peers == 1 ? ' peer' : ' peers'),
          if (formattedRate != null) ...[
            const TextSpan(text: ' · '),
            TextSpan(
              text: separator < 0 ? formattedRate : formattedRate.substring(0, separator),
              style: numberStyle,
            ),
            if (separator >= 0) TextSpan(text: formattedRate.substring(separator)),
          ],
        ],
      ),
      textAlign: TextAlign.center,
      style: FlickText.metadata.copyWith(color: FlickTokens.textSecondary),
    );
  }
}
