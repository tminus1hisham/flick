import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/material.dart';

import '../state.dart';
import 'detail.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final records = downloads.records;
          if (records.isEmpty) {
            return const Center(child: Text('No downloads yet'));
          }
          return ListView(children: [
            FutureBuilder<int>(
              future: downloads.bytesUsed(),
              builder: (_, s) => ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: Text('Using ${((s.data ?? 0) / (1 << 30)).toStringAsFixed(2)} GB'),
              ),
            ),
            for (final r in records) _tile(context, r),
          ]);
        },
      );

  Widget _tile(BuildContext context, TaskRecord r) {
    final item = downloads.itemOf(r);
    final poster = downloads.posterOf(item.id);
    final done = r.status == TaskStatus.complete;
    final running = r.status == TaskStatus.running || r.status == TaskStatus.enqueued;
    return ListTile(
      leading: SizedBox(
        width: 48,
        child: poster.existsSync() ? Image.file(poster, fit: BoxFit.cover) : const Icon(Icons.movie),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: done
          ? const Text('Ready offline')
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.status.name),
              if (running) LinearProgressIndicator(value: r.progress < 0 ? null : r.progress),
            ]),
      onTap: done ? () => play(context, item) : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (running && r.task.allowPause)
          IconButton(icon: const Icon(Icons.pause), onPressed: () => downloads.pause(r)),
        if (r.status == TaskStatus.paused)
          IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => downloads.resume(r)),
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => downloads.delete(r)),
      ]),
    );
  }
}
