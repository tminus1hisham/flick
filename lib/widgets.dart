import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' show ClientException;

import 'jellyfin.dart';
import 'screens/detail.dart';
import 'state.dart';
import 'theme.dart';

void openItem(BuildContext context, Item item) => Navigator.push(
    context, MaterialPageRoute(builder: (_) => DetailScreen(item: item)));

/// A sentence a viewer can act on, instead of an exception dump.
String friendlyError(Object e) => switch (e) {
      SocketException() || ClientException() || TimeoutException() =>
        "Can't reach your server. Check your connection and try again.",
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

/// Signed-in server details and sign out.
class ProfileButton extends StatelessWidget {
  const ProfileButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Profile',
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Signed in to', style: Theme.of(sheet).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(Uri.tryParse(session.client?.server ?? '')?.authority ?? '',
                      style: Theme.of(sheet).textTheme.titleSmall),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheet);
                      session.logout();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
        icon: CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Icon(Icons.person_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
