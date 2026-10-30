import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import '../downloads.dart';
import '../jellyfin.dart';
import '../state.dart';
import '../theme.dart';
import 'account.dart';
import 'detail.dart';
import 'player.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final records = downloads.records;
          // Files from an earlier sign-in still list and play; only an empty guest list asks to sign in.
          if (records.isEmpty) return session.loggedIn ? const _Empty() : const SignInPrompt();
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
            for (final r in records) _row(r),
          ]);
        },
      );

  Widget _row(TaskRecord r) {
    final item = downloads.itemOf(r);
    return DownloadRow(
      record: r, item: item, poster: downloads.posterOf(item.id), stream: downloads.streamOf(r),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.movie_outlined, size: 48, color: cs.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('No downloads yet', style: t.titleMedium),
          const SizedBox(height: 4),
          Text('Downloaded videos will appear here.',
              textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

/// One download row. Public only so previews can render it without the manager.
class DownloadRow extends StatelessWidget {
  const DownloadRow({super.key, required this.record, required this.item, required this.poster, this.stream});
  final TaskRecord record;
  final Item item;
  final File poster;
  final StreamDownload? stream;

  Future<void> _playStream(BuildContext context) async {
    final path = await downloads.localPath(record.taskId);
    if (path == null || !context.mounted) return;
    final p = stream!.playback;
    final title = p.subtitle == null ? stream!.title : '${stream!.title} · ${p.subtitle}';
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(
      item: Item({'Id': p.videoId, 'Name': title, 'Type': 'Video'}),
      source: path, report: false, headers: const {}, playback: p,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final r = record;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fc = context.flick;
    final done = r.status == TaskStatus.complete;
    final running = r.status == TaskStatus.running || r.status == TaskStatus.enqueued;
    final paused = r.status == TaskStatus.paused;

    final (String label, IconData icon, Color color) = switch (r.status) {
      TaskStatus.running => ('Downloading', Icons.arrow_downward, cs.primary),
      TaskStatus.enqueued || TaskStatus.waitingToRetry => ('Waiting', Icons.schedule, cs.onSurfaceVariant),
      TaskStatus.paused => ('Paused', Icons.pause_circle_outline, fc.warning),
      TaskStatus.complete => ('Ready offline', Icons.check_circle_outline, fc.success),
      TaskStatus.failed || TaskStatus.notFound => ('Failed', Icons.report_outlined, fc.danger),
      TaskStatus.canceled => ('Canceled', Icons.cancel_outlined, cs.onSurfaceVariant),
    };

    final known = r.progress >= 0 && r.progress <= 1;
    final total = r.expectedFileSize;
    final showBytes = known && total > 0 && !done;
    String gb(num b) => (b / (1 << 30)).toStringAsFixed(2);
    final showBar = r.status == TaskStatus.running || ((running || paused) && known);

    return InkWell(
      onTap: done ? () => stream == null ? play(context, item) : _playStream(context) : null,
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
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                  if (stream?.playback.subtitle case final String subtitle) ...[
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
                    Text('${gb(r.progress * total)} / ${gb(total)} GB',
                        style: monoStyle.copyWith(fontSize: 12, height: 16 / 12, color: cs.onSurfaceVariant)),
                  ],
                  if (showBar) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: known ? r.progress : MediaQuery.disableAnimationsOf(context) ? 0 : null,
                      minHeight: 3,
                      color: paused ? fc.warning : cs.primary,
                      backgroundColor: cs.surfaceContainerHigh,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (running && r.task.allowPause)
            IconButton(
              tooltip: 'Pause download',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.pause),
              onPressed: () => downloads.pause(r),
            ),
          // Addon tasks retain their own request headers and do not need a Jellyfin session.
          if (paused && (stream != null || session.loggedIn))
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
              icon: const Icon(Icons.more_vert),
              itemBuilder: (_) => [
                PopupMenuItem(onTap: () => downloads.delete(r), child: const Text('Delete download')),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
