import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flick/stall.dart';
import '../kit/focus.dart';
import 'package:flick/theme.dart';
import 'package:flick/torrent.dart';

/// Playback status with a pass-through surface and an optional source action.
class BufferingPanel extends StatefulWidget {
  const BufferingPanel({required this.view, required this.onSwitch,
    required this.title, this.logo, this.poster, this.waiting = false, super.key});

  final BufferView view;
  final VoidCallback onSwitch;
  final String title;
  final String? logo, poster;
  /// A new buffering episode can still be inside its 600 ms suppression window.
  final bool waiting;

  @override
  State<BufferingPanel> createState() => _BufferingPanelState();
}

class _BufferingPanelState extends State<BufferingPanel> {
  BufferView? _lastVisible;
  bool _shown = false;
  Timer? _dismiss;
  bool _completing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
      if (_lastVisible == null) return;
      if (widget.waiting || MediaQuery.disableAnimationsOf(context)) {
        _dismiss?.cancel();
        _lastVisible = null;
        _shown = false;
        _completing = false;
        return;
      }
      if (_completing) return;
      _completing = true;
      _lastVisible = (
        phase: _lastVisible!.phase, progress: 1,
        stats: _lastVisible!.stats, offerSwitch: false,
      );
      _dismiss = Timer(FlickTokens.artworkFadeDuration, () {
        if (!mounted) return;
        setState(() => _shown = false);
        _dismiss = Timer(FlickTokens.stateDuration, () {
          if (mounted) {
            setState(() {
              _lastVisible = null;
              _completing = false;
            });
          }
        });
      });
      return;
    }
    _dismiss?.cancel();
    _completing = false;
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
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: FlickTokens.grid * 6, vertical: FlickTokens.grid * 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IgnorePointer(
                        child: _PhaseText(view.phase, enter: enter, exit: exit),
                      ),
                      const SizedBox(height: FlickTokens.grid * 4),
                      IgnorePointer(
                        child: ArtworkProgress(
                          title: widget.title,
                          logo: widget.logo,
                          poster: widget.poster,
                          progress: view.progress,
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
                                        child: context.tv
                                            ? FocusFrame.button(
                                                semanticLabel: 'Try another source', onActivate: widget.onSwitch,
                                                child: const Padding(padding: EdgeInsets.all(12),
                                                  child: Text('Try another source', style: FlickTv.body)),
                                              )
                                            : Material(
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
              style: FlickText.cardTitle.copyWith(color: FlickTokens.textPrimary),
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
                    style: (context.tv ? FlickTv.body : FlickText.body).copyWith(color: FlickTokens.textSecondary),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('online')),
        ),
      ],
    );
  }
}

/// The same artwork in two layers: a translucent base and a clipped clear reveal.
class ArtworkProgress extends StatelessWidget {
  const ArtworkProgress({required this.title, required this.progress,
    this.logo, this.poster, super.key});

  final String title;
  final String? logo, poster;
  final double? progress;

  Widget _layers(Widget artwork, double progress) => Stack(children: [
    Opacity(opacity: 0.25, child: artwork),
    Positioned.fill(child: ClipRect(clipper: _ArtworkReveal(progress), child: artwork)),
  ]);

  Widget _artwork(double progress) {
    final text = _layers(Text(title, textAlign: TextAlign.center,
      maxLines: 2, overflow: TextOverflow.ellipsis,
      style: FlickText.railHeading.copyWith(color: FlickTokens.accent)), progress);
    Widget image(String url, Widget fallback) => Image.network(url,
      fit: BoxFit.contain,
      frameBuilder: (_, child, frame, _) => frame == null ? text : _layers(child, progress),
      errorBuilder: (_, _, _) => fallback);
    final cover = poster == null || poster!.isEmpty ? text : image(poster!, text);
    return logo == null || logo!.isEmpty ? cover : image(logo!, cover);
  }

  @override
  Widget build(BuildContext context) {
    final value = progress == null || !progress!.isFinite
        ? 0.0 : progress!.clamp(0.0, 1.0).toDouble();
    return ExcludeSemantics(
      child: SizedBox(
        width: double.infinity,
        height: FlickTokens.grid * 18,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: value),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero : FlickTokens.artworkFadeDuration,
          curve: FlickTokens.curveIn,
          builder: (context, value, child) => Center(child: _artwork(value)),
        ),
      ),
    );
  }
}

class _ArtworkReveal extends CustomClipper<Rect> {
  const _ArtworkReveal(this.progress);
  final double progress;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * progress, size.height);

  @override
  bool shouldReclip(_ArtworkReveal oldClipper) => progress != oldClipper.progress;
}

class _BufferStats extends StatelessWidget {
  const _BufferStats(this.stats);

  final ({int peers, int? rate}) stats;

  @override
  Widget build(BuildContext context) {
    final numberStyle = streamMonoStyle.copyWith(color: FlickTokens.textSecondary, fontSize: context.tv ? 14 : 12);
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
      style: (context.tv ? FlickTv.meta : FlickText.metadata).copyWith(color: FlickTokens.textSecondary),
    );
  }
}
