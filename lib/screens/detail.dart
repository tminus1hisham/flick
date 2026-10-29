import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import '../jellyfin.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'account.dart';
import 'player.dart';

bool canDownload(TaskStatus? s) =>
    s == null || s == TaskStatus.canceled || s == TaskStatus.failed || s == TaskStatus.notFound;

Future<void> play(BuildContext context, Item item) async {
  final local = await downloads.localPath(item.id);
  // A guest's download whose file is gone: there is no server to stream it from instead.
  if (local == null && session.client == null) return;
  if (session.online) {
    // The passed-in item's resume position may be stale.
    try {
      item = await session.client!.item(item.id);
    } catch (_) {}
  }
  if (!context.mounted) return;
  await Navigator.push(context,
      MaterialPageRoute(builder: (_) => PlayerScreen(item: item, source: local)));
}

Future<Quality?> pickQuality(BuildContext context) => showModalBottomSheet<Quality>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Download quality', style: Theme.of(sheet).textTheme.titleMedium),
            ),
            for (final q in Quality.values)
              ListTile(
                title: Text(q.label),
                subtitle: Text(q == Quality.original
                    ? 'Full file, resumes if interrupted'
                    : 'Smaller file, restarts if interrupted'),
                onTap: () => Navigator.pop(context, q),
              ),
          ]),
        ),
      ),
    );

Future<void> download(BuildContext context, List<Item> items) async {
  items = [for (final i in items) if (canDownload(downloads.recordFor(i.id)?.status)) i];
  if (items.isEmpty) return;
  final q = await pickQuality(context);
  if (q == null) return;
  for (final i in items) {
    await downloads.enqueue(session.client!, i, q);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Queued ${items.length} download(s)')));
  }
}

String _duration(Duration d) =>
    d.inMinutes >= 60 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';

class DetailScreen extends StatefulWidget {
  const DetailScreen({required this.item, super.key});
  final Item item;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final Future<Item> _full = session.client!.item(widget.item.id);
  Future<List<Item>>? _seasons;
  Item? _season;
  Future<List<Item>>? _episodes;

  @override
  void initState() {
    super.initState();
    if (widget.item.type == 'Series') {
      _seasons = session.client!.seasons(widget.item.id).then((s) {
        if (s.isNotEmpty) _selectSeason(s.first);
        return s;
      });
    }
  }

  void _selectSeason(Item s) => setState(() {
        _season = s;
        _episodes = session.client!.episodes(widget.item.id, s.id);
      });

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      body: Stack(children: [
        ListView(padding: EdgeInsets.only(bottom: 28 + MediaQuery.paddingOf(context).bottom), children: [
          FutureBuilder<Item>(
            future: _full,
            builder: (_, s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _hero(s.data ?? item),
              // Disabled until the full item arrives, so a tap never races the server's state; if that
              // fetch fails they start from the item that opened the page.
              _Saving(s.data ?? item,
                  ready: s.connectionState == ConnectionState.done,
                  key: ValueKey(s.connectionState == ConnectionState.done)),
            ]),
          ),
          if (_seasons != null) _seasonSection(),
        ]),
        // Pinned so the way back stays reachable once the artwork scrolls away.
        Positioned(
          top: MediaQuery.paddingOf(context).top + 4,
          left: 8,
          child: BackButton(
            style: IconButton.styleFrom(backgroundColor: FlickTokens.background.withValues(alpha: 0.45)),
          ),
        ),
      ]),
    );
  }

  Widget _hero(Item full) {
    final c = session.client!;
    final item = widget.item;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final progress = progressOf(full);
    final overview = full.overview ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 300),
        // passthrough hands the minimum to the column so spaceBetween pins the copy to the bottom.
        child: Stack(fit: StackFit.passthrough, children: [
          Positioned.fill(
            child: NetImage(c.backdropUrl(item.seriesId ?? item.id), fallback: c.imageUrl(item.id), icon: false),
          ),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: context.flick.scrimTop))),
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: context.flick.scrimBottom))),
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.paddingOf(context).top + 56),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(full.title, style: text.headlineSmall),
                  FutureBuilder<List<Item>>(
                    future: _seasons,
                    builder: (_, s) {
                      final n = s.data?.length;
                      final meta = [
                        if (full.year != null) '${full.year}',
                        if (full.runtime != null && full.runtime! > Duration.zero) _duration(full.runtime!),
                        if (n != null && n > 0) '$n season${n == 1 ? '' : 's'}',
                        ?timeLeft(full),
                      ];
                      return meta.isEmpty
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(meta.join(' · '), style: text.labelMedium?.copyWith(color: muted)),
                            );
                    },
                  ),
                  if (overview.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(overview,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(color: muted)),
                  ],
                ]),
              ),
            ],
          ),
        ]),
      ),
      if (item.playable)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (progress != null) ...[
              ClipRRect(borderRadius: BorderRadius.circular(2), child: Seam(progress)),
              const SizedBox(height: 16),
            ],
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: playButtonStyle(context),
                  onPressed: () => play(context, item),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(full.resumePosition > Duration.zero ? 'Resume' : 'Play'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: DownloadButton(item)),
            ]),
          ]),
        ),
    ]);
  }

  Widget _seasonSection() => FutureBuilder<List<Item>>(
        future: _seasons,
        builder: (context, s) {
          if (s.hasError) return ErrorState(s.error!);
          final seasons = s.data;
          if (seasons == null) return const _EpisodesSkeleton(tabs: true);
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            _SeasonTabs(seasons, selected: _season, onSelect: _selectSeason),
            if (_episodes != null)
              FutureBuilder<List<Item>>(
                future: _episodes,
                builder: (context, e) {
                  if (e.hasError) return ErrorState(e.error!, onRetry: () => _selectSeason(_season!));
                  if (!e.hasData) return const _EpisodesSkeleton();
                  final eps = e.data!;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                      child: Row(children: [
                        Expanded(
                          child: Text('${eps.length} episode${eps.length == 1 ? '' : 's'}',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        TextButton.icon(
                          onPressed: () => download(context, eps),
                          icon: const Icon(Icons.download),
                          label: const Text('Download season'),
                        ),
                      ]),
                    ),
                    for (final ep in eps) _EpisodeRow(ep),
                  ]);
                },
              ),
          ]);
        },
      );
}

/// Scrollable season tabs with a red underline under the selected one.
class _SeasonTabs extends StatelessWidget {
  const _SeasonTabs(this.seasons, {required this.selected, required this.onSelect});
  final List<Item> seasons;
  final Item? selected;
  final ValueChanged<Item> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelLarge;
    return Container(
      height: 48,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final se in seasons)
            Semantics(
              selected: se.id == selected?.id,
              button: true,
              child: InkWell(
                onTap: () => onSelect(se),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        width: 3,
                        color: se.id == selected?.id ? scheme.primary : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Text(se.name,
                      style: style?.copyWith(
                          color: se.id == selected?.id ? scheme.onSurface : scheme.onSurfaceVariant)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow(this.ep);
  final Item ep;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final progress = progressOf(ep);
    final meta = timeLeft(ep) ?? (ep.runtime != null ? _duration(ep.runtime!) : null);
    final watched = ep.json['UserData']?['Played'] == true;
    return InkWell(
      onTap: () => play(context, ep),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
            child: SizedBox(
              width: 112,
              height: 63,
              child: Stack(fit: StackFit.expand, children: [
                NetImage(session.client!.imageUrl(ep.id, maxHeight: 300)),
                if (progress != null) Align(alignment: Alignment.bottomCenter, child: Seam(progress)),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ep.episode == null ? ep.name : 'E${ep.episode} · ${ep.name}',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
              if (meta != null) Text(meta, style: text.labelMedium?.copyWith(color: muted)),
              ListenableBuilder(
                listenable: downloads,
                builder: (context, _) {
                  final r = downloads.recordFor(ep.id);
                  final dl = switch (r?.status) {
                    final s when canDownload(s) => null,
                    TaskStatus.complete => (Icons.download_done, 'Downloaded'),
                    TaskStatus.paused => (Icons.pause_circle_outline, 'Paused'),
                    _ => (Icons.downloading, 'Downloading ${((r!.progress.clamp(0, 1)) * 100).round()}%'),
                  };
                  final states = [
                    if (watched) (Icons.check_circle, 'Watched', context.flick.success),
                    if (dl != null) (dl.$1, dl.$2, muted),
                  ];
                  if (states.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 12, runSpacing: 4, children: [
                      for (final (icon, label, color) in states)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 4),
                          Text(label, style: text.labelMedium?.copyWith(color: color)),
                        ]),
                    ]),
                  );
                },
              ),
              if ((ep.overview ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(ep.overview!,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: muted)),
              ],
            ]),
          ),
          SizedBox.square(dimension: 48, child: DownloadButton(ep, compact: true)),
        ]),
      ),
    );
  }
}

class _EpisodesSkeleton extends StatelessWidget {
  const _EpisodesSkeleton({this.tabs = false});
  final bool tabs;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (tabs) ...[
            const Row(children: [
              Skeleton(width: 72, height: 20, radius: 4),
              SizedBox(width: 24),
              Skeleton(width: 72, height: 20, radius: 4),
            ]),
            const SizedBox(height: 24),
          ],
          for (var i = 0; i < 3; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Skeleton(width: 112, height: 63),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Skeleton(width: 160, height: 16, radius: 4),
                    SizedBox(height: 8),
                    Skeleton(width: 80, height: 12, radius: 4),
                    SizedBox(height: 8),
                    Skeleton(height: 12, radius: 4),
                  ]),
                ),
              ]),
            ),
        ]),
      );
}

/// Favourite + like for a Jellyfin title, saved to the server. Flips at once, reverts on failure.
class _Saving extends StatefulWidget {
  const _Saving(this.item, {required this.ready, super.key});
  final Item item;
  final bool ready;

  @override
  State<_Saving> createState() => _SavingState();
}

class _SavingState extends State<_Saving> {
  late bool _favourite = widget.item.isFavorite, _liked = widget.item.liked;
  final _busy = <String>{};
  bool _failed = false;

  /// Optimistic: answers true at once so the toggle's haptic lands with the flip, not the response.
  bool _set(String what, bool on, void Function(bool) apply, Future<void> Function(String, bool) send) {
    if (!_busy.add(what)) return false;
    _send(what, on, apply, send);
    return true;
  }

  Future<void> _send(String what, bool on, void Function(bool) apply, Future<void> Function(String, bool) send) async {
    setState(() {
      _failed = false;
      apply(on);
    });
    try {
      await send(widget.item.id, on);
    } catch (_) {
      if (mounted) {
        setState(() {
          apply(!on);
          _failed = true;
        });
      }
    }
    _busy.remove(what);
  }

  @override
  Widget build(BuildContext context) {
    final c = session.client!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, FlickTokens.grid * 4, FlickTokens.pageGutter, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: FlickTokens.grid * 2, runSpacing: FlickTokens.grid * 2, children: [
          ToggleAction(
            on: _favourite,
            icon: Icons.favorite_border_rounded,
            onIcon: Icons.favorite_rounded,
            label: 'Add to favourites',
            onLabel: 'Remove from favourites',
            onPressed: !widget.ready
                ? null
                : () async => _set('favourite', !_favourite, (v) => _favourite = v, c.setFavorite),
          ),
          ToggleAction(
            on: _liked,
            icon: Icons.thumb_up_outlined,
            onIcon: Icons.thumb_up_rounded,
            label: 'Like title',
            onLabel: 'Unlike title',
            onPressed: !widget.ready ? null : () async => _set('like', !_liked, (v) => _liked = v, c.setLiked),
          ),
        ]),
        if (_failed) ...[
          const SizedBox(height: FlickTokens.grid * 2),
          Semantics(
            liveRegion: true,
            child: Text("Couldn't save. Try again.",
                style: FlickText.metadata.copyWith(color: context.flick.danger)),
          ),
        ],
      ]),
    );
  }
}

class DownloadButton extends StatelessWidget {
  const DownloadButton(this.item, {this.compact = false, super.key});
  final Item item;
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final r = downloads.recordFor(item.id);
          final (icon, label) = switch (r?.status) {
            final s when canDownload(s) => (Icons.download, 'Download'),
            TaskStatus.complete => (Icons.download_done, 'Downloaded'),
            TaskStatus.paused => (Icons.pause_circle_outline, 'Paused'),
            _ => (Icons.downloading, '${((r!.progress.clamp(0, 1)) * 100).round()}%'),
          };
          final onPressed = canDownload(r?.status) ? () => download(context, [item]) : null;
          return compact
              ? IconButton(onPressed: onPressed, icon: Icon(icon), tooltip: label)
              : OutlinedButton.icon(
                  // Keep the state readable when there is nothing to press.
                  style: OutlinedButton.styleFrom(
                    disabledForegroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                    disabledIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onPressed,
                  icon: Icon(icon),
                  label: Text(label),
                );
        },
      );
}
