import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'torrent.dart';

const _posters = [
  'assets/posters/p01.webp',
  'assets/posters/p02.webp',
  'assets/posters/p03.webp',
  'assets/posters/p04.webp',
  'assets/posters/p05.webp',
  'assets/posters/p06.webp',
  'assets/posters/p07.webp',
  'assets/posters/p08.webp',
  'assets/posters/p09.webp',
  'assets/posters/p10.webp',
  'assets/posters/p11.webp',
  'assets/posters/p12.webp',
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _signUp = false;
  bool _showPass = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_server, _user, _pass, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var server = _server.text.trim();
      if (!server.startsWith('http')) server = 'http://$server';
      await session.login(server, _user.text.trim(), _pass.text);
      // Opened from a gate or the profile sheet: return to where the user was.
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setMode(bool signUp) => setState(() {
    _signUp = signUp;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pushed = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      backgroundColor: FlickTokens.background,
      // The poster wall stays full-screen; only the form moves for the keyboard.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          const Positioned.fill(child: PosterDrift(assets: _posters)),
          Semantics(
            // Read after the guest link, which sits first visually (top right) but last in the Stack.
            sortKey: const OrdinalSortKey(1),
            container: true,
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: CustomScrollView(
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Column(
                      children: [
                        // Room for the guest link above the mark.
                        SafeArea(bottom: false, child: _Brand(top: !pushed && !session.onboarded ? 64 : 40)),
                        const Spacer(),
                        _panel(context, reduceMotion),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Top right, where "skip" lives: under the form it falls below the fold on a 640dp phone.
          if (!pushed && !session.onboarded)
            Positioned(
              top: MediaQuery.paddingOf(context).top + FlickTokens.grid,
              right: FlickTokens.grid * 2,
              child: Semantics(
                sortKey: const OrdinalSortKey(0),
                container: true,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor: FlickTokens.background.withValues(alpha: 0.45),
                    minimumSize: const Size(0, FlickTokens.minTouchTarget),
                  ),
                  onPressed: _busy ? null : session.continueAsGuest,
                  child: const Text('Continue as guest'),
                ),
              ),
            ),
          if (pushed)
            Positioned(
              top: MediaQuery.paddingOf(context).top + FlickTokens.grid,
              left: FlickTokens.grid * 2,
              child: IconButton(
                tooltip: 'Close sign in',
                style: IconButton.styleFrom(backgroundColor: FlickTokens.background.withValues(alpha: 0.45)),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context, bool reduceMotion) {
    // Sign up is visual-only until there's a backend for it.
    final message =
        _error ??
        (_signUp ? "Sign up isn't available yet. Ask your server's admin for an account." : null);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FlickTokens.surface1.withValues(alpha: 0.88),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(FlickTokens.modalRadius)),
        border: const Border(top: BorderSide(color: FlickTokens.outline)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ModeSwitch(signUp: _signUp, onChanged: _busy ? null : _setMode),
              const SizedBox(height: 20),
              _Field(
                'Jellyfin server',
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.url],
                  decoration: const InputDecoration(hintText: 'http://192.168.1.10:8096'),
                ),
              ),
              const SizedBox(height: 12),
              _Field(
                'Username',
                TextField(
                  controller: _user,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  autofillHints: [_signUp ? AutofillHints.newUsername : AutofillHints.username],
                ),
              ),
              const SizedBox(height: 12),
              _Field(
                'Password',
                TextField(
                  controller: _pass,
                  obscureText: !_showPass,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: _signUp ? TextInputAction.next : TextInputAction.done,
                  autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                  onSubmitted: _signUp ? null : (_) => _submit(),
                  decoration: InputDecoration(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      ),
                      tooltip: _showPass ? 'Hide password' : 'Show password',
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: reduceMotion ? Duration.zero : FlickTokens.artworkFadeDuration,
                curve: FlickTokens.curveIn,
                alignment: Alignment.topCenter,
                child: _signUp
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: _Field(
                          'Confirm password',
                          TextField(
                            controller: _confirm,
                            obscureText: !_showPass,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _error != null ? Icons.error_outline : Icons.info_outline,
                          size: 16,
                          color: _error != null ? FlickTokens.danger : FlickTokens.textSecondary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message,
                            style: FlickText.metadata.copyWith(
                              color: _error != null
                                  ? FlickTokens.danger
                                  : FlickTokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                style: playButtonStyle(
                  context,
                ).copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52))),
                onPressed: _busy || _signUp ? null : _submit,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_signUp ? 'Create account' : 'Sign in'),
              ),
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: FlickTokens.textSecondary,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => openMagnet(context),
                child: const Text('Stream a link instead'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label above a filled field. The theme's outline border would float a labelText onto the
/// field's edge, so the label sits outside and is handed to the field's semantics instead.
class _Field extends StatelessWidget {
  const _Field(this.label, this.field);
  final String label;
  final Widget field;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
      const SizedBox(height: 8),
      Semantics(label: label, child: field),
    ],
  );
}

class _Brand extends StatelessWidget {
  const _Brand({required this.top});
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, top, 20, 24),
    child: Column(
      children: [
        const FlickMark(size: 48, label: null),
        const SizedBox(height: 12),
        Text('Flick', style: FlickText.heroTitle.copyWith(color: FlickTokens.textPrimary)),
        const SizedBox(height: 8),
        Text(
          'Your next obsession starts here.',
          textAlign: TextAlign.center,
          style: FlickText.body.copyWith(color: FlickTokens.textPrimary),
        ),
      ],
    ),
  );
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.signUp, required this.onChanged});

  final bool signUp;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(value: false, label: Text('Sign in')),
      ButtonSegment(value: true, label: Text('Sign up')),
    ],
    selected: {signUp},
    showSelectedIcon: false,
    expandedInsets: EdgeInsets.zero,
    onSelectionChanged: onChanged == null ? null : (s) => onChanged!(s.single),
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      side: const WidgetStatePropertyAll(BorderSide.none),
      textStyle: const WidgetStatePropertyAll(FlickText.button),
      // Grey, not white: the white primary button stays the one bright control.
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? FlickTokens.outline : FlickTokens.surface2,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? FlickTokens.textPrimary : FlickTokens.textSecondary,
      ),
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : FlickTokens.stateDuration,
    ),
  );
}

/// A tilted wall of poster columns drifting up and down behind the form.
class PosterDrift extends StatefulWidget {
  const PosterDrift({super.key, required this.assets});

  final List<String> assets;

  @override
  State<PosterDrift> createState() => _PosterDriftState();
}

class _PosterDriftState extends State<PosterDrift> with SingleTickerProviderStateMixin {
  static const _angle = -12 * math.pi / 180;
  static const _gap = 12.0;
  // Loops per controller period; that's 24 / 30 / 40 / 30 s per poster.
  static const _cycles = [5, 4, 3, 4];
  static const _offsets = [0.0, .31, .57, .79];

  late final _clock = AnimationController(
    vsync: this,
    duration: Duration(seconds: math.max(1, widget.assets.length) * 120),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final a in widget.assets) {
      precacheImage(
        ResizeImage.resizeIfNeeded(300, null, AssetImage(a)),
        context,
        onError: (_, _) {},
      );
    }
    // The mixin's ticker already pauses when TickerMode is off (route covered).
    final animate = widget.assets.isNotEmpty && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!animate && _clock.isAnimating) {
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  Widget _column(int index, double width, double height) {
    final n = widget.assets.length;
    final loopHeight = (width * 1.5 + _gap) * n;
    final copies = (height / loopHeight).ceil() + 1;
    final strip = RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var copy = 0; copy < copies; copy++)
            for (var row = 0; row < n; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: _gap),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
                  child: Image.asset(
                    widget.assets[(row + index * 3) % n],
                    width: width,
                    height: width * 1.5,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => SizedBox(
                      width: width,
                      height: width * 1.5,
                      child: const ColoredBox(color: FlickTokens.surface2),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );

    return Positioned(
      left: index * (width + _gap),
      top: 0,
      width: width,
      child: AnimatedBuilder(
        animation: _clock,
        child: strip,
        builder: (_, child) {
          final direction = index.isEven ? 1.0 : -1.0;
          final phase = (_offsets[index] + direction * _clock.value * _cycles[index]) % 1.0;
          return Transform.translate(offset: Offset(0, -phase * loopHeight), child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              final cos = math.cos(_angle), sin = math.sin(_angle).abs();
              // Viewport bounds in the rotated wall's coordinates, so no corner shows a gap.
              final needWidth = size.width * cos + size.height * sin + 24;
              final wallHeight = size.height * cos + size.width * sin + 24;
              final posterWidth = math.max(144.0, (needWidth - 3 * _gap) / 4);
              final wallWidth = posterWidth * 4 + 3 * _gap;
              return Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: FlickTokens.background),
                  if (widget.assets.isNotEmpty)
                    OverflowBox(
                      minWidth: wallWidth,
                      maxWidth: wallWidth,
                      minHeight: wallHeight,
                      maxHeight: wallHeight,
                      child: Transform.rotate(
                        angle: _angle,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (var i = 0; i < 4; i++) _column(i, posterWidth, wallHeight),
                          ],
                        ),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, .25, .45, .60, 1],
                        colors: [
                          for (final a in const [.28, .42, .85, .98, 1.0])
                            FlickTokens.background.withValues(alpha: a),
                        ],
                      ),
                    ),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -.35),
                        radius: .9,
                        stops: [.45, 1],
                        colors: [Colors.transparent, Color(0x73000000)],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
