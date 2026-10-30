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
    final stats = view.phase == BufferPhase.offline ? null : view.stats;
    final panel = SizedBox(
      width: FlickTokens.grid * 80,
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
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: FlickTokens.surface1,
                      borderRadius: BorderRadius.circular(FlickTokens.modalRadius),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                alignment: Alignment.topCenter,
                duration: enter,
                curve: FlickTokens.curveIn,
                child: Padding(
                  padding: const EdgeInsets.all(FlickTokens.grid * 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IgnorePointer(
                        child: _PhaseText(view.phase, enter: enter, exit: exit),
                      ),
                      const SizedBox(height: FlickTokens.grid * 4),
                      IgnorePointer(
                        child: _BufferRail(
                          progress: view.progress,
                          offline: view.phase == BufferPhase.offline,
                          enter: enter,
                        ),
                      ),
                      IgnorePointer(
                        child: _FadeContent(
                          enter: enter,
                          exit: exit,
                          child: stats == null
                              ? const SizedBox.shrink(key: ValueKey('no-stats'))
                              : Padding(
                                  key: const ValueKey('stats'),
                                  padding: const EdgeInsets.only(top: FlickTokens.railGap),
                                  child: _BufferStats(stats),
                                ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: !offered,
                        child: ExcludeSemantics(
                          excluding: !offered,
                          child: ExcludeFocus(
                            excluding: !offered,
                            child: _FadeContent(
                              enter: enter,
                              exit: exit,
                              child: view.offerSwitch
                                  ? Padding(
                                      key: const ValueKey('action'),
                                      padding: const EdgeInsets.only(
                                        top: FlickTokens.grid * 4,
                                      ),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          minWidth: double.infinity,
                                          minHeight: FlickTokens.minTouchTarget,
                                        ),
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: OutlinedButton(
                                            onPressed: widget.onSwitch,
                                            child: Text(
                                              'Try another source',
                                              style: FlickText.metadata.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                  : const SizedBox.shrink(key: ValueKey('no-action')),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Above centre: a new row grows the card mostly downward (AnimatedSize) and it always fits.
    return Align(alignment: const Alignment(0, -0.3), child: panel);
  }
}

class _FadeContent extends StatelessWidget {
  const _FadeContent({
    required this.enter,
    required this.exit,
    required this.child,
  });

  final Duration enter;
  final Duration exit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AnimatedSwitcher(
        duration: enter,
        reverseDuration: exit,
        switchInCurve: FlickTokens.curveIn,
        switchOutCurve: FlickTokens.curveOut,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.topLeft,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          );
        },
        child: child,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          container: true,
          liveRegion: true,
          label: title,
          excludeSemantics: true,
          child: _FadeContent(
            enter: enter,
            exit: exit,
            child: Text(
              title,
              key: ValueKey(phase),
              textAlign: TextAlign.start,
              style: FlickText.railHeading.copyWith(color: FlickTokens.textPrimary),
            ),
          ),
        ),
        _FadeContent(
          enter: enter,
          exit: exit,
          child: phase == BufferPhase.offline
              ? Padding(
                  key: const ValueKey('offline'),
                  padding: const EdgeInsets.only(top: FlickTokens.grid * 2),
                  child: Text(
                    'Playback will resume automatically.',
                    textAlign: TextAlign.start,
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
  const _BufferRail({
    required this.progress,
    required this.offline,
    required this.enter,
  });

  final double? progress;
  final bool offline;
  final Duration enter;

  @override
  Widget build(BuildContext context) {
    final value = progress?.clamp(0.0, 1.0).toDouble();

    return ExcludeSemantics(
      child: Opacity(
        opacity: offline ? 0.4 : 1,
        child: SizedBox(
          height: FlickTokens.grid,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: value ?? 0),
            duration: enter,
            curve: FlickTokens.curveIn,
            builder: (context, animatedValue, child) {
              return Row(
                children: [
                  for (var index = 0; index < 6; index++) ...[
                    if (index > 0) const SizedBox(width: FlickTokens.grid),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(FlickTokens.grid),
                        child: ColoredBox(
                          color: FlickTokens.outline,
                          child: value == null
                              ? const SizedBox.expand()
                              : Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: (animatedValue * 6 - index)
                                        .clamp(0.0, 1.0)
                                        .toDouble(),
                                    heightFactor: 1,
                                    child: const ColoredBox(color: FlickTokens.progress),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
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
    final numberStyle = streamMonoStyle.copyWith(color: FlickTokens.textSecondary);
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
      textAlign: TextAlign.start,
      style: FlickText.metadata.copyWith(color: FlickTokens.textSecondary),
    );
  }
}
