import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import '../downloads.dart';
import '../kit/sheet.dart';
import '../state.dart';
import '../theme.dart';
import 'player.dart';
import 'native_downloads.dart' as native;

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          // Only stream downloads play; a record without stream metadata is skipped.
          final records = [
            for (final r in downloads.records)
              if (downloads.streamOf(r) case final stream?) (r, stream),
          ];
          final torrents = downloads.torrentRecords;
          if (records.isEmpty && torrents.isEmpty && !downloads.torrentError) return native.NativeDownloadsScreen(onPlay: (d) => _playNative(context, d));
          final cs = Theme.of(context).colorScheme;
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 16, FlickTokens.pageGutter, 8),
              child: FutureBuilder<int>(
                future: downloads.bytesUsed(),
                builder: (_, s) => Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Flick downloads · '),
                    TextSpan(
                      text: '${((s.data ?? 0) / (1 << 30)).toStringAsFixed(2)} GB',
                      style: monoStyle.copyWith(color: cs.onSurface),
                    ),
                  ]),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
            if (downloads.torrentError)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    liveRegion: true,
                    child: Text("Couldn't update torrent downloads. Check your connection and try again.",
                        style: FlickText.metadata.copyWith(color: context.flick.warning)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: downloads.restoreTorrents,
                    child: const Text('Try again'),
                  ),
                ]),
              ),
            for (final d in downloads.items)
              native.DownloadRow(download: d, onPlay: (d) => _playNative(context, d)),
            for (final r in torrents)
              DownloadRow.torrent(download: r, poster: downloads.posterOf(r.taskId)),
            for (final (r, stream) in records)
              DownloadRow(record: r, poster: downloads.posterOf(r.taskId), stream: stream),
          ]);
        },
      );
}

/// One download row. Public only so previews can render it without the manager.
class DownloadRow extends StatefulWidget {
  const DownloadRow({super.key, required this.record, required this.poster, required StreamDownload this.stream})
      : torrent = null;
  const DownloadRow.torrent({
    super.key, required TorrentDownload download, required this.poster,
  }) : torrent = download, record = null, stream = null;
  final TaskRecord? record;
  final TorrentDownload? torrent;
  final File poster;
  final StreamDownload? stream;

  @override
  State<DownloadRow> createState() => _DownloadRowState();
}

class _DownloadRowState extends State<DownloadRow> {
  String? _error;
  bool _deleting = false;

  StreamDownload get _stream => widget.torrent?.stream ?? widget.stream!;
  String get _taskId => widget.torrent?.taskId ?? widget.record!.taskId;

  Future<void> _playStream() async {
    try {
      final path = await downloads.localPath(_taskId);
      if (!mounted) return;
      if (path == null) {
        setState(() => _error = 'Downloaded file is missing. Delete it and download again.');
        return;
      }
      setState(() => _error = null);
      final stream = _stream;
      final p = stream.playback;
      final title = p.subtitle == null ? stream.title : '${stream.title} · ${p.subtitle}';
      await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
        title: title, source: path, headers: const {}, playback: p,
      )));
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't open this download. Try again.");
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      final torrent = widget.torrent;
      if (torrent != null) {
        await downloads.deleteTorrent(torrent);
      } else {
        await downloads.delete(widget.record!);
      }
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't delete this download. Try again.");
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final torrent = widget.torrent;
    final stream = _stream;
    final poster = widget.poster;
    final status = torrent?.status ?? r!.status;
    final progress = torrent?.progress ?? r!.progress;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fc = context.flick;
    final done = status == TaskStatus.complete;
    final running = status == TaskStatus.running || status == TaskStatus.enqueued;
    final paused = status == TaskStatus.paused;

    final (String label, IconData icon, Color color) = switch (status) {
      TaskStatus.running => ('Downloading', Icons.arrow_downward, cs.primary),
      TaskStatus.enqueued || TaskStatus.waitingToRetry => ('Waiting', Icons.schedule, cs.onSurfaceVariant),
      TaskStatus.paused => ('Paused', Icons.pause_circle_outline, fc.warning),
      TaskStatus.complete => ('Ready offline', Icons.check_circle_outline, fc.success),
      TaskStatus.failed || TaskStatus.notFound => ('Failed', Icons.report_outlined, fc.danger),
      TaskStatus.canceled => ('Canceled', Icons.cancel_outlined, cs.onSurfaceVariant),
    };

    final known = progress >= 0 && progress <= 1;
    final total = torrent?.expectedFileSize ?? r!.expectedFileSize;
    final showBytes = known && total > 0 && !done;
    String gb(num b) => (b / (1 << 30)).toStringAsFixed(2);
    final showBar = status == TaskStatus.running || ((running || paused) && known);
    final error = _error ?? torrent?.info?.error;

    return InkWell(
      onTap: done && !_deleting ? _playStream : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 16, 4, 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outline))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
            child: SizedBox(
              width: 56,
              height: 84,
              child: poster.existsSync()
                  ? Image.file(poster, fit: BoxFit.cover)
                  : ColoredBox(
                      color: cs.surfaceContainerHigh,
                      child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 84),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(stream.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                  if (stream.playback.subtitle case final String subtitle) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(label, style: t.labelMedium?.copyWith(color: color), overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                  if (showBytes) ...[
                    const SizedBox(height: 2),
                    Text('${gb(progress * total)} / ${gb(total)} GB',
                        style: monoStyle.copyWith(fontSize: 12, height: 16 / 12, color: cs.onSurfaceVariant)),
                  ],
                  if (showBar) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: known ? progress : MediaQuery.disableAnimationsOf(context) ? 0 : null,
                      minHeight: 3,
                      color: paused ? fc.warning : cs.primary,
                      backgroundColor: cs.surfaceContainerHigh,
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(error, style: FlickText.metadata.copyWith(color: fc.danger)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (running && r != null && r.task.allowPause)
            IconButton(
              tooltip: 'Pause download',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.pause),
              onPressed: () => downloads.pause(r),
            ),
          // Tasks keep their own request headers, so they resume as they were queued.
          if (paused && r != null)
            IconButton(
              tooltip: 'Resume download',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.play_arrow),
              onPressed: () => downloads.resume(r),
            ),
          SizedBox(
            width: 48,
            height: 48,
            child: PopupMenuButton<void>(
              tooltip: 'More actions',
              enabled: !_deleting,
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                PopupMenuItem(onTap: _delete, child: const Text('Delete download')),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

void _playNative(BuildContext context, Download d) {
  if (!File(d.path).existsSync()) {
    showFlickSheet<void>(context, (_) => const Padding(
      padding: EdgeInsets.all(FlickTokens.pageGutter),
      child: Text('Downloaded file is missing. Delete it and download again.'),
    ));
    return;
  }
  Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
    title: d.playback.title, source: d.path, playback: d.playback,
  )));
}
