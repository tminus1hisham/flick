import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kit/sheet.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart' show NetImage;
import 'login.dart';

/// Actions that need a Jellyfin account.
enum Gate {
  favourite('Sign in to save favourites'),
  like('Sign in to like titles'),
  download('Sign in to download');

  const Gate(this.title);
  final String title;
}

/// True when signed in, now or after the sign-in sheet and Login.
/// The caller then performs the action, preserving the original intent.
/// [poster] is the artwork of the title being saved, shown in the sheet.
Future<bool> requireSignIn(BuildContext context, Gate gate, {String? poster}) async {
  if (session.loggedIn) return true;
  final go = await showFlickSheet<bool>(context, (_) => SignInSheet(gate, poster: poster));
  if (go != true || !context.mounted) return false;
  return openSignIn(context);
}

/// Login as a pushed route; it pops itself after a successful sign-in.
Future<bool> openSignIn(BuildContext context) async {
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
  );
  return session.loggedIn;
}

/// Why an account is needed, Sign in, Not now. Pops true for Sign in; the title's poster
/// (or the Flick mark for downloads) shows what is being saved.
class SignInSheet extends StatelessWidget {
  const SignInSheet(this.gate, {this.poster, super.key});

  final Gate gate;
  final String? poster;

  IconData get _icon => switch (gate) {
        Gate.favourite => Icons.favorite_rounded,
        Gate.like => Icons.thumb_up_rounded,
        Gate.download => Icons.download_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FlickTokens.stateDuration;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FlickTokens.pageGutter,
          FlickTokens.grid,
          FlickTokens.pageGutter,
          FlickTokens.pageGutter,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  // No artwork to show (downloads, or a title without a poster): the Flick mark.
                  child: gate == Gate.download || (poster ?? '').trim().isEmpty
                      ? const SizedBox(
                          width: FlickTokens.grid * 12,
                          child: FlickMark(
                            size: FlickTokens.grid * 12,
                            label: null,
                          ),
                        )
                      : _GatePoster(poster: poster, icon: _icon),
                ),
                const SizedBox(width: FlickTokens.grid * 4),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      gate.title,
                      style: FlickText.railHeading.copyWith(
                        color: FlickTokens.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FlickTokens.grid * 4),
            Text(
              'Flick accounts are Jellyfin server accounts. Browsing and playing stay open without one.',
              style: FlickText.body.copyWith(
                color: FlickTokens.textSecondary,
              ),
            ),
            const SizedBox(height: FlickTokens.grid * 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(
                        FlickTokens.minTouchTarget,
                        FlickTokens.minTouchTarget,
                      ),
                      animationDuration: duration,
                      foregroundColor: FlickTokens.textSecondary,
                      textStyle: FlickText.button,
                    ),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: FlickTokens.railGap),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(
                        FlickTokens.minTouchTarget,
                        FlickTokens.minTouchTarget,
                      ),
                      animationDuration: duration,
                      backgroundColor: FlickTokens.accent,
                      foregroundColor: FlickTokens.onAccent,
                      textStyle: FlickText.button,
                    ),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Sign in'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GatePoster extends StatelessWidget {
  const _GatePoster({required this.poster, required this.icon});

  final String? poster;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: FlickTokens.grid * 16,
      height: FlickTokens.grid * 23,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            width: FlickTokens.grid * 14,
            height: FlickTokens.grid * 21,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  FlickTokens.artworkRadius,
                ),
                border: Border.all(color: FlickTokens.outline),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  FlickTokens.artworkRadius,
                ),
                // Only built with a poster; SignInSheet shows the Flick mark otherwise.
                child: NetImage(poster!.trim(), icon: false),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: FlickTokens.grid * 6,
              height: FlickTokens.grid * 6,
              decoration: const BoxDecoration(
                color: FlickTokens.accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: FlickTokens.grid * 4,
                color: FlickTokens.onAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Controlled favourite / like toggle.
///
/// The caller owns gating, persistence and optimistic state. [onPressed] answers whether the
/// state changed: a dismissed sign-in gate answers false and stays silent.
class ToggleAction extends StatefulWidget {
  const ToggleAction({
    required this.on,
    required this.icon,
    required this.onIcon,
    required this.label,
    required this.onLabel,
    required this.onPressed,
    super.key,
  });

  final bool on;
  final IconData icon, onIcon;

  /// Spoken action while off and while on.
  final String label, onLabel;
  final Future<bool> Function()? onPressed;

  @override
  State<ToggleAction> createState() => _ToggleActionState();
}

class _ToggleActionState extends State<ToggleAction> {
  bool _down = false;

  Future<void> _activate() async {
    final turningOn = !widget.on;
    if (await widget.onPressed?.call() ?? false) {
      turningOn ? HapticFeedback.lightImpact() : HapticFeedback.selectionClick();
    }
  }

  @override
  void didUpdateWidget(covariant ToggleAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onPressed != null;
    final label = widget.on ? widget.onLabel : widget.label;
    final color = !enabled
        ? FlickTokens.textSecondary
        : widget.on
            ? FlickTokens.accent
            : FlickTokens.textPrimary;

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      toggled: widget.on,
      label: label,
      onTap: enabled ? _activate : null,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: AnimatedScale(
          scale: _down && !reduceMotion ? 0.97 : 1,
          duration: reduceMotion ? Duration.zero : FlickTokens.stateDuration,
          curve: FlickTokens.curveIn,
          child: Material(
            color: FlickTokens.surface1,
            borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              excludeFromSemantics: true,
              onTap: enabled ? _activate : null,
              onHighlightChanged: (down) {
                if (_down != down) setState(() => _down = down);
              },
              child: SizedBox.square(
                dimension: FlickTokens.minTouchTarget,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : FlickTokens.stateDuration,
                    switchInCurve: FlickTokens.curveIn,
                    switchOutCurve: FlickTokens.curveOut,
                    transitionBuilder: (child, animation) {
                      final fade = FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                      if (reduceMotion) return fade;
                      return ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.9,
                          end: 1,
                        ).animate(animation),
                        child: fade,
                      );
                    },
                    child: Icon(
                      widget.on ? widget.onIcon : widget.icon,
                      key: ValueKey(widget.on),
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Guest Downloads empty state: a muted strip of the Login poster wall, then the way in.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key});

  static const _assets = <String>[
    'assets/posters/p01.webp',
    'assets/posters/p02.webp',
    'assets/posters/p03.webp',
    'assets/posters/p04.webp',
    'assets/posters/p05.webp',
    'assets/posters/p06.webp',
    'assets/posters/p07.webp',
    'assets/posters/p08.webp',
  ];

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        FlickTokens.pageGutter,
        FlickTokens.grid * 4,
        FlickTokens.pageGutter,
        FlickTokens.pageGutter,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  FlickTokens.artworkRadius,
                ),
                child: SizedBox(
                  width: double.infinity,
                  // Tall enough for whole posters to read; PosterDrift stops itself under reduced motion.
                  height: FlickTokens.grid * 40,
                  child: const PosterDrift(assets: _assets),
                ),
              ),
            ),
          ),
          const SizedBox(height: FlickTokens.grid * 5),
          Semantics(
            header: true,
            child: Text(
              'Your library, ready offline',
              style: FlickText.railHeading.copyWith(
                color: FlickTokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: FlickTokens.grid * 2),
          Text(
            'Sign in to your Jellyfin server to download titles '
            'and take them with you.',
            style: FlickText.body.copyWith(
              color: FlickTokens.textSecondary,
            ),
          ),
          const SizedBox(height: FlickTokens.grid * 6),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(
                FlickTokens.minTouchTarget,
                FlickTokens.minTouchTarget,
              ),
              backgroundColor: FlickTokens.accent,
              foregroundColor: FlickTokens.onAccent,
              textStyle: FlickText.button,
              animationDuration:
                  reduceMotion ? Duration.zero : FlickTokens.stateDuration,
            ),
            onPressed: () => openSignIn(context),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
