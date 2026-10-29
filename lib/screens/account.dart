import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kit/sheet.dart';
import '../state.dart';
import '../theme.dart';
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
Future<bool> requireSignIn(BuildContext context, Gate gate) async {
  if (session.loggedIn) return true;
  final go = await showFlickSheet<bool>(context, (_) => SignInSheet(gate));
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

/// Why an account is needed, Sign in, Not now.
/// Pops true for Sign in; dismissal leaves the action unchanged.
class SignInSheet extends StatelessWidget {
  const SignInSheet(this.gate, {super.key});

  final Gate gate;

  IconData get _icon => switch (gate) {
        Gate.favourite => Icons.favorite_border_rounded,
        Gate.like => Icons.thumb_up_outlined,
        Gate.download => Icons.download_outlined,
      };

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
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
              Align(
                alignment: Alignment.centerLeft,
                child: ExcludeSemantics(
                  child: Container(
                    width: FlickTokens.minTouchTarget,
                    height: FlickTokens.minTouchTarget,
                    decoration: BoxDecoration(
                      color: FlickTokens.surface2,
                      borderRadius: BorderRadius.circular(
                        FlickTokens.controlRadius,
                      ),
                    ),
                    child: Icon(
                      _icon,
                      color: FlickTokens.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: FlickTokens.grid * 4),
              Semantics(
                header: true,
                child: Text(
                  gate.title,
                  style: FlickText.pageTitle.copyWith(
                    color: FlickTokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: FlickTokens.grid * 2),
              Text(
                'Your Jellyfin server account. '
                'Favourites and downloads follow you.',
                style: FlickText.body.copyWith(
                  color: FlickTokens.textSecondary,
                ),
              ),
              const SizedBox(height: FlickTokens.grid * 6),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign in'),
              ),
              const SizedBox(height: FlickTokens.grid * 2),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: FlickTokens.textSecondary,
                ),
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      );
}

/// Controlled favourite / like toggle.
///
/// The caller owns gating, persistence and optimistic state. Haptics follow
/// state changes after activation, so opening or dismissing a gate is silent.
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
  final VoidCallback? onPressed;

  @override
  State<ToggleAction> createState() => _ToggleActionState();
}

class _ToggleActionState extends State<ToggleAction> {
  bool _down = false;
  bool _activated = false;

  void _activate() {
    if (widget.onPressed == null) return;
    _activated = true;
    widget.onPressed!();
  }

  @override
  void didUpdateWidget(covariant ToggleAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.on != oldWidget.on) {
      if (_activated) {
        if (widget.on) {
          HapticFeedback.lightImpact();
        } else {
          HapticFeedback.selectionClick();
        }
      }
      _activated = false;
    }
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
                    duration: FlickTokens.stateDuration,
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

/// Guest Downloads empty state. Existing downloads take precedence.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(FlickTokens.pageGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: FlickTokens.grid * 16,
                    height: FlickTokens.grid * 16,
                    decoration: BoxDecoration(
                      color: FlickTokens.surface1,
                      borderRadius: BorderRadius.circular(
                        FlickTokens.controlRadius,
                      ),
                    ),
                    child: const Icon(
                      Icons.download_outlined,
                      size: FlickTokens.grid * 8,
                      color: FlickTokens.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: FlickTokens.grid * 5),
              Semantics(
                header: true,
                child: Text(
                  Gate.download.title,
                  textAlign: TextAlign.center,
                  style: FlickText.pageTitle.copyWith(
                    color: FlickTokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: FlickTokens.grid * 2),
              Text(
                'Downloads come from your Jellyfin library.',
                textAlign: TextAlign.center,
                style: FlickText.body.copyWith(
                  color: FlickTokens.textSecondary,
                ),
              ),
              const SizedBox(height: FlickTokens.grid * 6),
              FilledButton(
                onPressed: () => openSignIn(context),
                child: const Text('Sign in'),
              ),
            ],
          ),
        ),
      );
}
