import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  TorrentEngine? _engine;
  int? _id; // the torrent this screen owns
  int _attempt = 0; // bumped by each start and by dispose; stale continuations clean up after themselves
  Timer? _poll;
  bool _polling = false;
  TorrentStatus? _info;
  List<TorrentFile>? _files;
  Object? _error;
  bool _busy = false, _opening = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final attempt = ++_attempt;
    bool stale() => attempt != _attempt || !mounted;
    _busy = true;
    try {
      final engine = _engine = await torrentEngine();
      if (stale()) return;
      final dir = await torrentDir();
      // Delete the directory only while no torrent can be using it; once add is invoked the startup
      // sweep owns any leftovers.
      if (stale()) return dir.delete(recursive: true).ignore();
      final id = await engine.add(widget.magnet, dir.path);
      if (stale()) return _forget(engine.remove(id));
      _id = id;
      _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
      _refresh();
    } catch (e) {
      if (!stale()) setState(() => _error = e);
    } finally {
      if (attempt == _attempt) _busy = false;
    }
  }

  Future<void> _refresh() async {
    final engine = _engine, id = _id;
    if (_polling || engine == null || id == null) return;
    _polling = true;
    try {
      final s = await engine.status(id);
      final files = s != null && s.hasMetadata && _files == null ? await engine.files(id) : null;
      if (!mounted || id != _id) return;
      setState(() {
        _info = s;
        if (files != null) {
          _files = files.where((f) => isVideo(f.name)).toList()
            ..sort((a, b) => b.size.compareTo(a.size));
        }
      });
    } catch (e) {
      if (mounted && id == _id) setState(() => _error = e);
    } finally {
      _polling = false;
    }
  }

  Future<void> _retry() async {
    if (_busy) return;
    _busy = true;
    await _teardown();
    if (!mounted) return;
    setState(() {
      _error = null;
      _info = null;
      _files = null;
    });
    _start();
  }

  Future<void> _play(TorrentFile f) async {
    final engine = _engine, id = _id;
    if (_opening || engine == null || id == null) return;
    _opening = true;
    try {
      final url = await engine.stream(id, f.index);
      if (!mounted || id != _id) return;
      try {
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PlayerScreen(
                    item: Item({'Id': 'torrent', 'Name': f.name}), source: url, report: false)));
      } finally {
        if (id == _id) _forget(engine.stopStream(id));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _opening = false;
    }
  }

  /// Removes the owned torrent (stops its streams and deletes its data natively).
  Future<void> _teardown() async {
    _poll?.cancel();
    _poll = null;
    final engine = _engine, id = _id;
    _id = null;
    if (engine != null && id != null) await _forget(engine.remove(id));
  }

  static Future<void> _forget(Future<void> f) =>
      f.catchError((Object e) => debugPrint('torrent teardown: $e'));

  @override
  void dispose() {
    _attempt++;
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    final error = _error ?? i?.error;
    final status = i == null ? 'Starting…' : '${i.peers} peers · ${_rate(i.rate)}';
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
