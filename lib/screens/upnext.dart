// Up Next card and the player bar's Next episode button (design/upnext.md, visual by Codex).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../kit/focus.dart';
import '../upnext.dart' show NextEpisode, UpNextView, countdownLength;
import '../widgets.dart' show NetImage, Skeleton;

class UpNextCard extends StatelessWidget {
  const UpNextCard({required this.view, required this.episode, required this.autoplay,
      required this.onNext, required this.onDismiss, required this.onAutoplay, super.key});

  final UpNextView view;
  final NextEpisode episode;
  final bool autoplay;
  final VoidCallback onNext, onDismiss;
  final ValueChanged<bool> onAutoplay;

  void _next() {
    HapticFeedback.lightImpact();
    onNext();
  }

  @override
  Widget build(BuildContext context) => _CardMotion(
        visible: view.visible,
        child: SizedBox(
          width: FlickTokens.grid * 90,
          child: Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: FlickTokens.surface1,
                    borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(FlickTokens.railGap),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    key: const ValueKey('episode-identity'),
                    container: true,
                    liveRegion: true,
                    label: 'Up next, ${episode.label}, ${episode.title}',
                    excludeSemantics: true,
                    child: IgnorePointer(child: _EpisodeHeader(episode)),
                  ),
                  const SizedBox(height: FlickTokens.railGap),
                  _tvFocus(context, view.resolving ? null : _next, _NextAction(view: view, onPressed: _next)),
                  const SizedBox(height: FlickTokens.grid),
                  Wrap(
                    spacing: FlickTokens.railGap,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: FlickTokens.grid * 36,
                        child: Material(
                          type: MaterialType.transparency,
                          child: _tvFocus(context, view.resolving ? null : onDismiss, TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: FlickTokens.textPrimary,
                              minimumSize: const Size(0, FlickTokens.minTouchTarget),
                              padding: const EdgeInsets.symmetric(horizontal: FlickTokens.grid * 2),
                              textStyle: FlickText.button,
                              animationDuration: Duration.zero,
                            ),
                            onPressed: view.resolving ? null : onDismiss,
                            child: const Text('Watch credits'),
                          )),
                        ),
                      ),
                      _tvFocus(context, view.resolving ? null : () => onAutoplay(!autoplay), _AutoplayControl(
                        value: autoplay,
                        onChanged: view.resolving ? null : onAutoplay,
                      )),
                    ],
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
}

Widget _tvFocus(BuildContext context, VoidCallback? onActivate, Widget child) => context.tv
    ? FocusFrame(onActivate: onActivate, child: ExcludeFocus(child: child)) : child;

// The label's font with tabular figures: RobotoMono's space read as a gap ("6  s"). Claude override, decisions.md.
const _seconds = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

class _NextAction extends StatelessWidget {
  const _NextAction({required this.view, required this.onPressed});

  final UpNextView view;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final counting = view.countdown != null;
    final progress = view.resolving ? 1.0 : view.countdown;
    final foreground = counting || view.resolving ? FlickTokens.onAccent : context.flick.playFg;
    final label = view.resolving
        ? 'Finding next episode…'
        : counting ? 'Next episode in ${view.secondsLeft} seconds' : 'Next episode';

    return Semantics(
      container: true,
      button: true,
      enabled: !view.resolving,
      label: label,
      onTap: view.resolving ? null : onPressed,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
          child: Stack(children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: counting || view.resolving ? FlickTokens.surface2 : context.flick.playBg,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress ?? 0,
                      heightFactor: 1,
                      child: ColoredBox(color: context.flick.progress),
                    ),
                  ),
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  disabledForegroundColor: foreground,
                  minimumSize: const Size(double.infinity, FlickTokens.minTouchTarget),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FlickTokens.railGap,
                    vertical: FlickTokens.grid * 2,
                  ),
                  textStyle: FlickText.button,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  animationDuration: Duration.zero,
                ),
                onPressed: view.resolving ? null : onPressed,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Visibility(
                      visible: !view.resolving,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.skip_next, size: FlickTokens.grid * 5),
                          const SizedBox(width: FlickTokens.grid * 2),
                          // Tight while counting: fills to push the seconds to the trailing edge.
                          Flexible(
                            fit: counting ? FlexFit.tight : FlexFit.loose,
                            child: const Text('Next episode', maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (counting) ...[
                            const SizedBox(width: FlickTokens.grid * 2),
                            Stack(
                              alignment: Alignment.centerRight,
                              children: [
                                Visibility(
                                  visible: false,
                                  maintainState: true,
                                  maintainAnimation: true,
                                  maintainSize: true,
                                  child: Text('${countdownLength.inSeconds} s', style: _seconds),
                                ),
                                Text('${view.secondsLeft} s', style: _seconds),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (view.resolving)
                      Text('Finding next episode…', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: FlickText.button.copyWith(color: foreground)),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AutoplayControl extends StatelessWidget {
  const _AutoplayControl({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: 'Autoplay next episode',
        toggled: value,
        enabled: onChanged != null,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ExcludeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged!(!value),
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: FlickTokens.minTouchTarget),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Autoplay', style: (context.tv ? FlickTv.meta : FlickText.metadata).copyWith(color: FlickTokens.textSecondary)),
                    const SizedBox(width: FlickTokens.grid * 2),
                    Switch(
                      value: value,
                      onChanged: onChanged,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      thumbColor: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected) ? FlickTokens.onAccent : FlickTokens.textSecondary),
                      trackColor: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected) ? FlickTokens.accent : FlickTokens.surface2),
                      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
                          states.contains(WidgetState.selected) ? FlickTokens.accent : FlickTokens.outline),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _EpisodeHeader extends StatefulWidget {
  const _EpisodeHeader(this.episode);

  final NextEpisode episode;

  @override
  State<_EpisodeHeader> createState() => _EpisodeHeaderState();
}

class _EpisodeHeaderState extends State<_EpisodeHeader> {
  // A failed thumbnail removes the image and its gap; the text takes the width.
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final url = _failed ? null : episode.thumbnail;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FlickTokens.grid * 13.5),
      child: Row(children: [
        if (url != null && url.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
            child: SizedBox(
              width: FlickTokens.grid * 24,
              height: FlickTokens.grid * 13.5,
              child: Stack(fit: StackFit.expand, children: [
                const Skeleton(radius: FlickTokens.artworkRadius),
                NetImage(url, icon: false, onError: () {
                  if (mounted) setState(() => _failed = true);
                }),
              ]),
            ),
          ),
          const SizedBox(width: FlickTokens.railGap),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(episode.label, style: (context.tv ? FlickTv.meta : FlickText.metadata).copyWith(color: FlickTokens.textSecondary)),
              const SizedBox(height: FlickTokens.grid),
              Text(episode.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: FlickText.cardTitle.copyWith(color: FlickTokens.textPrimary)),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Fades and settles 8 dp up on enter, back down on exit; out of input, focus and semantics at once when hidden.
class _CardMotion extends StatelessWidget {
  const _CardMotion({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = visible ? FlickTokens.artworkFadeDuration : FlickTokens.stateDuration;
    final curve = visible ? FlickTokens.curveIn : FlickTokens.curveOut;
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: duration,
            curve: curve,
            child: AnimatedSlide(
              // ~8 dp of the ~190 dp card.
              offset: visible || reduced ? Offset.zero : const Offset(0, 0.04),
              duration: reduced ? Duration.zero : duration,
              curve: curve,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class NextEpisodeButton extends StatelessWidget {
  const NextEpisodeButton({required this.onPressed, super.key});

  final VoidCallback? onPressed;

  void _next() {
    HapticFeedback.lightImpact();
    onPressed!();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        enabled: onPressed != null,
        label: 'Play next episode',
        onTap: onPressed == null ? null : _next,
        child: ExcludeSemantics(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: FlickTokens.textPrimary,
              minimumSize: const Size(FlickTokens.minTouchTarget, FlickTokens.minTouchTarget),
              padding: const EdgeInsets.symmetric(horizontal: FlickTokens.railGap),
              textStyle: FlickText.button,
              animationDuration: Duration.zero,
            ),
            onPressed: onPressed == null ? null : _next,
            icon: const Icon(Icons.skip_next, size: FlickTokens.grid * 5),
            label: const Padding(
              padding: EdgeInsets.only(left: FlickTokens.grid),
              child: Text('Next episode'),
            ),
          ),
        ),
      );
}
