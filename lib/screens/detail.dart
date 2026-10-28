import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import '../jellyfin.dart';
import '../state.dart';
import 'player.dart';

bool canDownload(TaskStatus? s) =>
    s == null || s == TaskStatus.canceled || s == TaskStatus.failed || s == TaskStatus.notFound;

Future<void> play(BuildContext context, Item item) async {
  final local = await downloads.localPath(item.id);
  if (session.online) {
    // The passed-in item's resume position may be stale.
    try {
      item = await session.client!.item(item.id);
    } catch (_) {}
  }
  if (!context.mounted) return;
  await Navigator.push(context,
      MaterialPageRoute(builder: (_) => PlayerScreen(item: item, localPath: local)));
}

Future<Quality?> pickQuality(BuildContext context) => showModalBottomSheet<Quality>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Download quality')),
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
    final c = session.client!;
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: Text(item.name)),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(c.imageUrl(item.id),
                  width: 120, errorBuilder: (_, _, _) => const SizedBox(width: 120)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FutureBuilder<Item>(
                future: _full,
                builder: (_, s) {
                  final full = s.data ?? item;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(full.title, style: Theme.of(context).textTheme.titleLarge),
                    Text([
                      if (full.year != null) '${full.year}',
                      if (full.runtime != null) '${full.runtime!.inMinutes} min',
                    ].join(' · ')),
                    const SizedBox(height: 8),
                    Text(full.overview ?? '', maxLines: 8, overflow: TextOverflow.ellipsis),
                  ]);
                },
              ),
            ),
          ]),
        ),
        if (item.playable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              FilledButton.icon(
                onPressed: () => play(context, item),
                icon: const Icon(Icons.play_arrow),
                label: Text(item.resumePosition > Duration.zero ? 'Resume' : 'Play'),
              ),
              const SizedBox(width: 12),
              DownloadButton(item),
            ]),
          ),
        if (_seasons != null) _seasonSection(),
      ]),
    );
  }

  Widget _seasonSection() => FutureBuilder<List<Item>>(
        future: _seasons,
        builder: (_, s) {
          final seasons = s.data ?? [];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 8, children: [
                for (final se in seasons)
                  ChoiceChip(
                    label: Text(se.name),
                    selected: se.id == _season?.id,
                    onSelected: (_) => _selectSeason(se),
                  ),
              ]),
            ),
            if (_episodes != null)
              FutureBuilder<List<Item>>(
                future: _episodes,
                builder: (context, e) {
                  if (!e.hasData) {
                    return const Padding(
                        padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                  }
                  final eps = e.data!;
                  return Column(children: [
                    ListTile(
                      title: Text('${eps.length} episodes'),
                      trailing: TextButton.icon(
                        onPressed: () => download(context, eps),
                        icon: const Icon(Icons.download),
                        label: const Text('Download season'),
                      ),
                    ),
                    for (final ep in eps)
                      ListTile(
                        title: Text('${ep.episode ?? ''}. ${ep.name}'),
                        subtitle: Text(ep.overview ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => play(context, ep),
                        trailing: DownloadButton(ep, compact: true),
                      ),
                  ]);
                },
              ),
          ]);
        },
      );
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
              : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
        },
      );
}
