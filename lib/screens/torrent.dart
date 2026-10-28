import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libtorrent_flutter/libtorrent_flutter.dart';

import '../jellyfin.dart';
import '../torrent.dart';
import 'player.dart';

bool _entryBusy = false;

/// Asks for a magnet link and streams it. Held from the tap until the torrent
/// screen closes, so only one torrent session exists at a time.
Future<void> openMagnet(BuildContext context) async {
  if (_entryBusy) return;
  _entryBusy = true;
  try {
    var clip = '';
    try {
      clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    } catch (_) {} // prefill is a convenience
    if (!context.mounted) return;
    final magnet = await showDialog<String>(
        context: context, builder: (_) => _MagnetDialog(isMagnet(clip) ? clip : ''));
    if (magnet == null || !context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TorrentScreen(magnet)));
  } finally {
    _entryBusy = false;
  }
}

class MagnetButton extends StatelessWidget {
  const MagnetButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
      icon: const Icon(Icons.add_link),
      tooltip: 'Play magnet link',
      onPressed: () => openMagnet(context));
}

class _MagnetDialog extends StatefulWidget {
  const _MagnetDialog(this.initial);
  final String initial;

  @override
  State<_MagnetDialog> createState() => _MagnetDialogState();
}

class _MagnetDialogState extends State<_MagnetDialog> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;
  bool _done = false;

  /// Pops at most once, so a tap during the exit animation cannot pop the route beneath.
  void _close([String? magnet]) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, magnet);
  }

  void _submit() {
    if (_done) return;
    final m = _text.text.trim();
    if (!isMagnet(m)) return setState(() => _error = 'Not a magnet link');
    _close(m);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Play magnet link'),
        content: TextField(
          controller: _text,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: 'magnet:?xt=urn:btih:…', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(onPressed: _close, child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Play')),
        ],
      );
}

class TorrentScreen extends StatefulWidget {
  const TorrentScreen(this.magnet, {super.key});
  final String magnet;

  @override
  State<TorrentScreen> createState() => _TorrentScreenState();
}

class _TorrentScreenState extends State<TorrentScreen> {
  LibtorrentFlutter? _engine;
  int? _id; // the torrent this screen owns
  final _streamIds = <int>{};
  StreamSubscription<Map<int, TorrentInfo>>? _sub;
  TorrentInfo? _info;
  List<FileInfo>? _files;
  Object? _error;
  bool _busy = false, _opening = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _busy = true;
    try {
      final engine = _engine = await torrentEngine();
      if (!mounted) return;
      final dir = await torrentDir();
      if (!mounted) return dir.delete(recursive: true).ignore();
      final id = _id = engine.addMagnet(widget.magnet, dir.path, true);
      _sub = engine.torrentUpdates.listen((all) {
        if (all[id] case final i?) _update(i);
      });
      if (engine.torrents[id] case final i?) _update(i);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _busy = false;
    }
  }

  void _update(TorrentInfo i) {
    if (!mounted || i.id != _id) return;
    setState(() {
      _info = i;
      if (i.hasMetadata && _files == null) {
        try {
          _files = _engine!.getFiles(i.id).where((f) => f.isStreamable).toList()
            ..sort((a, b) => b.size.compareTo(a.size));
        } catch (e) {
          _error = e;
        }
      }
    });
  }

  void _retry() {
    if (_busy) return;
    _teardown();
    setState(() {
      _error = null;
      _info = null;
      _files = null;
    });
    _start();
  }

  Future<void> _play(FileInfo f) async {
    final engine = _engine, id = _id;
    if (_opening || engine == null || id == null) return;
    _opening = true;
    try {
      final s = engine.startStream(id, fileIndex: f.index, maxCacheBytes: 64 << 20);
      _streamIds.add(s.id);
      try {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PlayerScreen(
                    item: Item({'Id': 'torrent', 'Name': f.name}), source: s.url, report: false)));
      } finally {
        // Unknown ids are a native no-op, so stop even if the poller dropped it.
        _streamIds.remove(s.id);
        _quietly(() => engine.stopStream(s.id));
      }
    } catch (e) {
      // ponytail: if startStream throws after creating the native stream (its status read failed),
      // the id never reaches us and native torrent removal does not stop streams, so that loopback
      // stream lives until the process exits; repeated failures accumulate. Needs a package fix.
      if (mounted) setState(() => _error = e);
    } finally {
      _opening = false;
    }
  }

  /// Stops and deletes the owned torrent. Each step runs even if an earlier one fails.
  void _teardown() {
    final sub = _sub;
    _sub = null;
    _quietly(() => sub?.cancel().catchError((Object e) => debugPrint('torrent teardown: $e')));
    final engine = _engine, id = _id;
    _id = null;
    if (engine == null || id == null) return;
    for (final s in _streamIds) {
      _quietly(() => engine.stopStream(s));
    }
    _streamIds.clear();
    _quietly(() => engine.stopAllStreamsForTorrent(id));
    // Not disposeTorrent: it no-ops until the poller has seen the torrent.
    _quietly(() => engine.removeTorrent(id, deleteFiles: true));
  }

  static void _quietly(void Function() f) {
    try {
      f();
    } catch (e) {
      debugPrint('torrent teardown: $e');
    }
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final error = _error ??
        (i != null && (i.state == TorrentState.error || i.errorMsg.isNotEmpty) ? i.errorMsg : null);
    final status = i == null ? 'Starting…' : '${i.numPeers} peers · ${_rate(i.downloadRate)}';
    return Scaffold(
      appBar: AppBar(title: Text(i == null || i.name.isEmpty ? 'Torrent' : i.name)),
      body: error != null
          ? _Message(
              'Could not play this torrent\n$error',
              action: FilledButton(onPressed: _retry, child: const Text('Retry')),
            )
          : _files == null
              ? _Message(i == null ? 'Starting…' : 'Fetching metadata · $status', busy: true)
              : _files!.isEmpty
                  ? const _Message('No playable video in this torrent')
                  : Column(children: [
                      ListTile(dense: true, title: Text(status)),
                      Expanded(
                        child: ListView(children: [
                          for (final f in _files!)
                            ListTile(
                              leading: const Icon(Icons.movie_outlined),
                              title: Text(f.name),
                              subtitle: Text(_size(f.size)),
                              onTap: () => _play(f),
                            ),
                        ]),
                      ),
                    ]),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.busy = false, this.action});
  final String text;
  final bool busy;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (busy) const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

String _size(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB'
    : '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';

String _rate(int bps) => '${(bps / (1 << 20)).toStringAsFixed(1)} MB/s';
