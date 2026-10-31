import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../addons.dart' show Subtitle;
import '../kit/route.dart';
import '../kit/sheet.dart';
import '../playback.dart';
import '../state.dart';
import '../theme.dart';
import '../torrent.dart';
import '../upnext.dart';
import '../widgets.dart';
import 'player.dart';

bool _entryBusy = false;

/// Asks for a magnet link and streams it. Held from the tap until the torrent
/// screen closes, so only one link entry flow exists at a time.
Future<void> openMagnet(BuildContext context) async {
  if (_entryBusy) return;
  _entryBusy = true;
  try {
    var clip = '';
    try {
      clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    } catch (_) {} // prefill is a convenience
    if (!context.mounted) return;
    final magnet = await showFlickSheet<String>(
        context, (_) => _MagnetDialog(isMagnet(clip) ? clip : ''));
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
      tooltip: 'Stream a link',
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
    if (!isMagnet(m)) return setState(() => _error = "That isn't a magnet link");
    _close(m);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            FlickTokens.pageGutter, 20, FlickTokens.pageGutter, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stream a link', style: FlickText.railHeading),
            const SizedBox(height: 12),
            Text('Paste a magnet link to choose a video.',
                style: FlickText.body.copyWith(color: FlickTokens.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(hintText: 'magnet:?xt=urn:btih:…', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 12, children: [
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _close,
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _submit,
                child: const Text('Continue'),
              ),
            ]),
          ],
        ),
      );
}

class TorrentScreen extends StatefulWidget {
  const TorrentScreen(this.magnet,
      {this.fileIdx, this.season, this.episode, this.title, this.playback, this.subtitles = const [], this.hash,
      this.next, this.download = false, this.poster, super.key});
  final String magnet;
  final int? fileIdx, season, episode;
  final String? title, poster;
  final Playback? playback;
  final List<Subtitle> subtitles;
  final String? hash;
  final bool download;

  /// Handed to the player; its answer comes back out of this route, which pops with it.
  final Future<NextUp?>? next;

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
  int? _openingFile; // UI only: the row showing "Opening…", tracks _opening
  int? _suggested;
  bool _autoAttempted = false;
  // Up Next: blank while the release before the next episode runs, so this screen doesn't cut back in.
  bool _handingOff = false;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final attempt = ++_attempt;
    bool stale() => attempt != _attempt || !mounted;
    _busy = true;
    _startedAt = DateTime.now();
    try {
      final engine = _engine = await torrentEngine();
      if (stale()) return;
      final dir = await torrentDir();
      // Delete the directory only while no torrent can be using it; once add is invoked the startup
      // sweep owns any leftovers.
      if (stale()) return dir.delete(recursive: true).ignore();
      final id = await engine.add(widget.magnet, dir.path);
      if (stale()) return _forget(engine.release(id));
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
    final attempt = _attempt;
    if (_polling || _error != null || engine == null || id == null) return;
    _polling = true;
    try {
      final s = await engine.status(id);
      final files = s != null && s.hasMetadata && _files == null ? await engine.files(id) : null;
      if (!mounted || id != _id || attempt != _attempt) return;
      TorrentFile? auto;
      setState(() {
        _info = s;
        if (s == null) {
          _error = 'This torrent is no longer available.';
        } else if (s.error != null) {
          _error = s.error;
        } else if (!s.hasMetadata &&
            DateTime.now().difference(_startedAt!) >= const Duration(seconds: 60)) {
          _error = 'No torrent details arrived. Try again or choose another source.';
        }
        if (files != null) {
          _files = files.where((f) => isVideo(f.name)).toList()
            ..sort((a, b) => b.size.compareTo(a.size));
          final guess = guessFile(_files!, season: widget.season, episode: widget.episode);
          _suggested = guess.index;
          TorrentFile? selected;
          for (final f in _files!) {
            if (f.index == widget.fileIdx) selected = f;
          }
          if (selected == null && guess.sure) {
            for (final f in _files!) {
              if (f.index == guess.index) selected = f;
            }
          }
          if (!_autoAttempted && selected != null && _error == null) {
            _autoAttempted = true;
            auto = selected;
          }
          _files!.sort((a, b) => a.index == b.index ? 0 : a.index == _suggested ? -1
              : b.index == _suggested ? 1 : b.size.compareTo(a.size));
        }
      });
      if (auto != null) _play(auto!, automatic: true);
    } catch (e) {
      if (mounted && id == _id && attempt == _attempt) setState(() => _error = e);
    } finally {
      _polling = false;
    }
  }

  Future<void> _retry() async {
    if (_busy || _opening) return;
    _busy = true;
    _attempt++;
    await _teardown(remove: true);
    if (!mounted) return;
    setState(() {
      _error = null;
      _info = null;
      _files = null;
      _suggested = null;
      _autoAttempted = false;
    });
    _start();
  }

  Future<void> _play(TorrentFile f, {bool automatic = false}) async {
    final engine = _engine, id = _id;
    if (_opening || engine == null || id == null) return;
    _opening = true;
    setState(() => _openingFile = f.index);
    try {
      if (widget.download) {
        final playback = widget.playback;
        if (playback == null) throw StateError('Download playback details are missing');
        await downloads.keepTorrent(
          engine, id, f.index,
          title: widget.title ?? playback.title,
          poster: widget.poster,
          playback: playback,
        );
        if (mounted && id == _id && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.pop(context, true);
        }
        return;
      }
      final url = await engine.stream(id, f.index);
      if (!mounted || id != _id) return;
      Object? result;
      try {
        result = await Navigator.push<Object?>(
            context,
            EpisodeRoute(
                builder: (_) => PlayerScreen(
                    title: widget.title ?? f.name,
                    source: url,
                    playback: widget.playback,
                    subtitles: widget.subtitles,
                    hash: widget.hash,
                    filename: f.name,
                    size: f.size,
                    torrent: (engine: engine, id: id),
                    next: widget.next)));
      } finally {
        if (id == _id) _forget(engine.stopStream(id));
      }
      // Up Next: hand the player's answer on to play(), from the file list too. The isCurrent check keeps a late
      // answer from popping a route pushed above this one.
      if (result != null && mounted && id == _id && ModalRoute.of(context)?.isCurrent == true) {
        // Release before popping: the next episode's add (same season pack) must come after it, or the release
        // from dispose would remove the torrent under it 60 s later.
        setState(() => _handingOff = true);
        await _teardown();
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent == true) {
          popForNext(context, result);
        } else {
          setState(() => _handingOff = false);
        }
      } else if (automatic && mounted && id == _id) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _opening = false;
      if (mounted) setState(() => _openingFile = null);
    }
  }

  /// Keep a released torrent warm; retries never delete a pre-existing kept download.
  Future<void> _teardown({bool remove = false}) async {
    _poll?.cancel();
    _poll = null;
    final engine = _engine, id = _id;
    _id = null;
    if (engine != null && id != null) {
      await _forget(remove ? engine.remove(id, unlessKept: true) : engine.release(id));
    }
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
    if (_handingOff) return const ColoredBox(color: FlickTokens.background);
    final i = _info, files = _files;
    final error = _error ?? i?.error;
    final t = Theme.of(context).textTheme;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget metric(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.labelMedium?.copyWith(color: secondary)),
            const SizedBox(height: 4),
            Text(value, style: monoStyle),
          ],
        );
    return Scaffold(
      appBar: AppBar(title: Text(widget.download ? 'Download' : widget.title ?? 'Stream a link')),
      body: error != null
          ? _Notice(
              icon: Icons.report_outlined,
              title: widget.download ? "Couldn't download this torrent" : "Couldn't play this torrent",
              detail: error is PlatformException ? error.message ?? error.code : '$error',
              danger: true,
              action: Wrap(spacing: 12, children: [
                OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: _retry, child: const Text('Retry')),
                TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Choose another source')),
              ]),
            )
          : files != null && files.isEmpty
              ? const _Notice(
                  icon: Icons.movie_outlined,
                  title: 'No playable video in this torrent',
                  detail: 'It has no video files the player can stream.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                      FlickTokens.pageGutter, 8, FlickTokens.pageGutter, FlickTokens.sectionGap),
                  children: [
                    _Stage('Starting', i == null ? _Step.now : _Step.done, busy: true),
                    _Stage(
                      'Reading torrent details',
                      i == null ? _Step.pending : (files == null ? _Step.now : _Step.done),
                      detail: i != null && files == null
                          ? 'Waiting for peers to send the file list'
                          : null,
                      busy: true,
                    ),
                    _Stage(
                        _autoAttempted && _openingFile != null
                            ? '${widget.download ? 'Queuing' : 'Opening'} ${files!.firstWhere((f) => f.index == _openingFile).name}'
                            : widget.download ? 'Choose a video to download' : 'Choose a video',
                        files == null ? _Step.pending : _Step.now),
                    if (i != null && i.name.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(i.name, style: t.titleMedium),
                    ],
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: metric('Peers', i == null ? '—' : '${i.peers}')),
                      Expanded(child: metric('Download speed', i == null ? '—' : formatRate(i.rate))),
                    ]),
                    if (i != null && files == null) ...[
                      const SizedBox(height: 16),
                      Text('Torrents with few peers can take a minute or more.',
                          style: t.bodyMedium?.copyWith(color: secondary)),
                    ],
                    if (files != null) ...[
                      const SizedBox(height: FlickTokens.sectionGap),
                      for (final (n, f) in files.indexed) ...[
                        if (n > 0) const Divider(),
                        _FileRow(f,
                            suggested: f.index == _suggested,
                            opening: _openingFile == f.index,
                            download: widget.download,
                            onTap: _opening ? null : () => _play(f)),
                      ],
                    ],
                  ],
                ),
    );
  }
}

enum _Step { done, now, pending }

/// One row of the status spine: a 3dp marker, the stage and its state.
class _Stage extends StatelessWidget {
  const _Stage(this.label, this.step, {this.detail, this.busy = false});
  final String label;
  final _Step step;
  final String? detail;

  /// Whether "now" means waiting on the engine rather than on the user.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final success = context.flick.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 3,
            constraints: const BoxConstraints(minHeight: 24),
            color: switch (step) {
              _Step.done => success,
              _Step.now => scheme.primary,
              _Step.pending => FlickTokens.outline,
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: t.bodyMedium?.copyWith(
                        color: step == _Step.pending ? scheme.onSurfaceVariant : null)),
                if (detail != null)
                  Text(detail!, style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ...switch (step) {
            _Step.done => [
                Icon(Icons.check, size: 16, color: success),
                const SizedBox(width: 4),
                Center(child: Text('Done', style: t.labelMedium?.copyWith(color: success))),
              ],
            _Step.now => [
                if (busy) ...const [
                  Center(child: Skeleton(width: 32, height: 12, radius: FlickTokens.controlRadius)),
                  SizedBox(width: 8),
                ],
                Center(child: Text('Now', style: t.labelMedium)),
              ],
            _Step.pending => const <Widget>[],
          },
        ]),
      ),
    );
  }
}

/// A flat, tappable video row: marker, wrapping name, size.
class _FileRow extends StatelessWidget {
  const _FileRow(this.file, {
    required this.suggested, required this.opening, required this.onTap, this.download = false,
  });
  final TorrentFile file;
  final bool suggested, opening, download;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: '${download ? 'Download' : 'Play'} ${file.name}, ${_size(file.size)}${suggested ? ', suggested' : ''}',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 3, color: opening ? scheme.primary : null),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (suggested)
                        // A filled tag: small red text on black would fall below 4.5:1.
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(FlickTokens.controlRadius)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.recommend_outlined, size: 16, color: scheme.onPrimary),
                                const SizedBox(width: 4),
                                Text('Suggested', style: t.labelSmall?.copyWith(
                                    color: scheme.onPrimary, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        ),
                      Text(file.name, style: t.bodyMedium),
                      if (opening)
                        Text(download ? 'Queuing…' : 'Opening…',
                            style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Center(
                child: Text(_size(file.size),
                    style: monoStyle.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Centred empty or error state: icon plus a written label, never colour alone.
class _Notice extends StatelessWidget {
  const _Notice(
      {required this.icon, required this.title, this.detail, this.danger = false, this.action});
  final IconData icon;
  final String title;
  final String? detail;
  final bool danger;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final tone = danger ? context.flick.danger : secondary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FlickTokens.pageGutter),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 32, color: tone),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: t.titleMedium?.copyWith(color: danger ? tone : null)),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(detail!,
                textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: secondary)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

String _size(int bytes) => bytes >= 1 << 30
    ? '${(bytes / (1 << 30)).toStringAsFixed(2)} GB'
    : '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
