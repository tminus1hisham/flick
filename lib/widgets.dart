import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' show ClientException;

import 'jellyfin.dart';
import 'kit/sheet.dart';
import 'screens/account.dart';
import 'screens/detail.dart';
import 'state.dart';
import 'theme.dart';

void openItem(BuildContext context, Item item) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => DetailScreen(item: item)));

/// A sentence a viewer can act on, instead of an exception dump.
String friendlyError(Object e) => switch (e) {
      SocketException() || ClientException() || TimeoutException() =>
        "Can't reach your server. Check your connection and try again.",
      JellyfinException(status: 400 || 401, :final path) when path.contains('AuthenticateByName') =>
        'Wrong username or password.',
      JellyfinException(status: 401) => 'Your session has expired. Sign out and sign in again.',
      JellyfinException(:final status) when status >= 500 =>
        'Your server had a problem (error $status). Try again in a moment.',
      JellyfinException(:final status) => 'Your server turned down the request (error $status).',
      _ => '$e',
    };

/// Series name for episodes, the item's own name otherwise.
String headline(Item i) => i.type == 'Episode' ? (i.seriesName ?? i.name) : i.name;

String? episodeLine(Item i) =>
    i.type == 'Episode' ? 'S${i.season ?? 0} · E${i.episode ?? 0} ${i.name}' : null;

/// Watched fraction, or null when the runtime is unknown or nothing was watched.
double? progressOf(Item i) {
  final r = i.runtime;
  if (r == null || r == Duration.zero || i.resumePosition == Duration.zero) return null;
  return (i.resumePosition.inSeconds / r.inSeconds).clamp(0.0, 1.0);
}

String? timeLeft(Item i) {
  final r = i.runtime;
  if (r == null || i.resumePosition == Duration.zero || i.resumePosition >= r) return null;
  final m = (r - i.resumePosition).inMinutes;
  return m >= 60 ? '${m ~/ 60} h ${m % 60} min left' : '$m min left';
}

/// Network artwork that fades in, falling back to [fallback] and then to a quiet placeholder.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {this.fallback, this.icon = true, super.key});
  final String url;
  final String? fallback;

  /// Whether the placeholder shows a media icon; off where text sits on the artwork.
  final bool icon;

  @override
  Widget build(BuildContext context) => Image.network(
        url,
        fit: BoxFit.cover,
        frameBuilder: (_, child, frame, sync) => sync
            ? child
            : AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: child,
              ),
        errorBuilder: (context, _, _) => fallback != null
            ? NetImage(fallback!, icon: icon)
            : ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                child: icon
                    ? Center(
                        child: Icon(Icons.movie_outlined,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      )
                    : null,
              ),
      );
}

/// The thin progress line under artwork.
class Seam extends StatelessWidget {
  const Seam(this.value, {super.key});
  final double value;

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
        value: value,
        minHeight: 3,
        borderRadius: BorderRadius.zero,
        backgroundColor: Colors.white24,
      );
}

/// A rounded block standing in for content that is still loading.
class Skeleton extends StatelessWidget {
  const Skeleton({this.width, this.height, this.radius = 8, super.key});
  final double? width, height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Library and search poster grid.
const posterGrid = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 130,
  childAspectRatio: 0.46,
  crossAxisSpacing: FlickTokens.railGap,
  mainAxisSpacing: 20,
);

/// Poster grid stand-in: artwork and a caption bar per cell, laid out by [delegate].
class GridSkeleton extends StatelessWidget {
  const GridSkeleton({required this.padding, this.delegate = posterGrid, super.key});
  final EdgeInsetsGeometry padding;
  final SliverGridDelegate delegate;

  @override
  Widget build(BuildContext context) => GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: delegate,
        itemCount: 12,
        itemBuilder: (_, _) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(aspectRatio: 2 / 3, child: Skeleton(radius: FlickTokens.artworkRadius)),
          SizedBox(height: 8),
          Skeleton(width: 80, height: 12, radius: 4),
        ]),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState(this.error, {this.onRetry, super.key});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.report_outlined, size: 32, color: context.flick.danger),
            const SizedBox(height: 12),
            Text(friendlyError(error),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ]),
        ),
      );
}

class Poster extends StatelessWidget {
  const Poster(this.item, {this.width = 112, super.key});
  final Item item;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => openItem(context, item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: NetImage(session.client!.imageUrl(item.id)),
                ),
              ),
              const SizedBox(height: 8),
              Text(item.type == 'Episode' ? item.title : item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class PosterRow extends StatelessWidget {
  const PosterRow(this.title, this.items, {super.key});
  final String title;
  final List<Item> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        SizedBox(
          height: 230 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => Poster(items[i]),
          ),
        ),
      ],
    );
  }
}

/// Signed-in server details and sign out; for a guest, what signing in gives and Sign in.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  Widget _content(List<Widget> children) => SafeArea(
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
            children: children,
          ),
        ),
      );

  Duration _duration(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : FlickTokens.stateDuration;

  Future<void> _guest(BuildContext context) async {
    final go = await showFlickSheet<bool>(
      context,
      (sheet) => _content([
        Semantics(
          header: true,
          child: Text(
            'Not signed in',
            style: FlickText.railHeading.copyWith(
              color: FlickTokens.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: FlickTokens.grid * 2),
        Text(
          'Browse and play as a guest. Sign in with your Jellyfin '
          'server account to save favourites, like titles and download.',
          style: FlickText.body.copyWith(
            color: FlickTokens.textSecondary,
          ),
        ),
        const SizedBox(height: FlickTokens.grid * 6),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: FlickTokens.accent,
            foregroundColor: FlickTokens.onAccent,
            minimumSize: const Size(
              FlickTokens.minTouchTarget,
              FlickTokens.minTouchTarget,
            ),
            textStyle: FlickText.button,
            animationDuration: _duration(sheet),
          ),
          onPressed: () => Navigator.pop(sheet, true),
          child: const Text('Sign in'),
        ),
      ]),
    );
    if (go == true && context.mounted) await openSignIn(context);
  }

  Future<void> _member(BuildContext context) async {
    final authority =
        Uri.tryParse(session.client?.server ?? '')?.authority ?? '';

    await showFlickSheet<void>(
      context,
      (sheet) => _content([
        Text(
          'Signed in to',
          style: FlickText.metadata.copyWith(
            color: FlickTokens.textSecondary,
          ),
        ),
        const SizedBox(height: FlickTokens.grid),
        Semantics(
          header: true,
          child: Text(
            authority.isEmpty ? 'Your Jellyfin server' : authority,
            softWrap: true,
            style: FlickText.railHeading.copyWith(
              color: FlickTokens.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: FlickTokens.grid * 6),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: FlickTokens.textPrimary,
            side: const BorderSide(color: FlickTokens.outline),
            minimumSize: const Size(
              FlickTokens.minTouchTarget,
              FlickTokens.minTouchTarget,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                FlickTokens.controlRadius,
              ),
            ),
            textStyle: FlickText.button,
            animationDuration: _duration(sheet),
          ),
          onPressed: () {
            Navigator.pop(sheet);
            session.logout();
          },
          icon: const ExcludeSemantics(child: Icon(Icons.logout_rounded)),
          label: const Text('Sign out'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: session.loggedIn ? 'Profile' : 'Sign in',
        style: IconButton.styleFrom(
          minimumSize: const Size(
            FlickTokens.minTouchTarget,
            FlickTokens.minTouchTarget,
          ),
          animationDuration: _duration(context),
        ),
        onPressed: () async {
          if (session.loggedIn) {
            await _member(context);
          } else {
            await _guest(context);
          }
        },
        icon: const ExcludeSemantics(
          child: CircleAvatar(
            radius: FlickTokens.grid * 4,
            backgroundColor: FlickTokens.surface2,
            child: Icon(
              Icons.person_outline_rounded,
              size: FlickTokens.grid * 5,
              color: FlickTokens.textSecondary,
            ),
          ),
        ),
      );
}

/// Renders [future]'s result, or [placeholder] / a retryable error.
class Loader<T> extends StatelessWidget {
  const Loader(this.future, this.builder, {this.onRetry, this.placeholder, super.key});
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback? onRetry;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, s) {
          if (s.hasError) return ErrorState(s.error!, onRetry: onRetry);
          if (!s.hasData) return placeholder ?? const Center(child: CircularProgressIndicator());
          return builder(s.data as T);
        },
      );
}

/// Takes over from the native splash: the mark sits exactly where Android drew
/// it while the app fades in underneath, then the mark fades away. 280 ms, no
/// waiting; the app is interactive from the first frame. Skipped under reduce
/// motion. Mounted once per engine start, so resuming the app never replays it.
class SplashHandoff extends StatefulWidget {
  const SplashHandoff({super.key, required this.child});

  final Widget child;

  /// Matches res/drawable/splash_mark.xml: Android 12's icon box without an
  /// icon background, drawn centred in the window.
  static const markSize = 288.0;
  static const duration = Duration(milliseconds: 280);

  @override
  State<SplashHandoff> createState() => _SplashHandoffState();
}

class _SplashHandoffState extends State<SplashHandoff> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: SplashHandoff.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(() {});
    });
  late final _content = CurvedAnimation(parent: _c, curve: const Interval(0, 120 / 280, curve: FlickTokens.curveIn));
  late final _markOut = CurvedAnimation(parent: _c, curve: const Interval(120 / 280, 1, curve: FlickTokens.curveIn));
  late final _mark = ReverseAnimation(_markOut);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _content.dispose();
    _markOut.dispose();
    _c.dispose();
    super.dispose();
  }

  // The child keeps its slot when the mark leaves, so app state survives.
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: FlickTokens.background,
        child: Stack(fit: StackFit.expand, children: [
          FadeTransition(opacity: _content, child: widget.child),
          if (!_c.isCompleted)
            IgnorePointer(
              child: FadeTransition(
                opacity: _mark,
                child: const Center(child: FlickMark.master(size: SplashHandoff.markSize)),
              ),
            ),
        ]),
      );
}
