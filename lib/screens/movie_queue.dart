import 'package:flutter/material.dart';

import '../addons.dart';
import '../kit/focus.dart';
import '../kit/queue_controls.dart';
import '../playback.dart';
import '../queue.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'title.dart';

typedef MovieChoice = ({QueuedMovie item, Addon addon, AddonStream stream});

/// Used by the play loop so an unavailable source pauses the queue for a choice.
Future<MovieChoice?> chooseQueuedMovie(BuildContext context, QueuedMovie item) =>
  Navigator.push<MovieChoice>(context, MaterialPageRoute(builder: (_) => MovieQueueScreen(initial: item, picking: true)));

class MovieQueueScreen extends StatefulWidget {
  const MovieQueueScreen({this.initial, this.picking = false, super.key});
  final QueuedMovie? initial;
  final bool picking;
  @override
  State<MovieQueueScreen> createState() => _MovieQueueScreenState();
}

class _MovieQueueScreenState extends State<MovieQueueScreen> {
  final _back = FocusNode(debugLabel: 'Playback queue Back');
  void _restoreFocus() { if (context.tv) _back.requestFocus(); }
  QueuedMovie? _selected;
  List<AddonStream>? _choices;
  Addon? _addon;
  String? _error;
  bool _busy = false, _clear = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _resolve(widget.initial!);
  }

  Future<void> _resolve(QueuedMovie item) async {
    if (_busy) return;
    final token = ++_generation;
    setState(() { _selected = item; _busy = true; _error = null; _choices = null; });
    try {
      final addon = addons.active.where((a) => a.base == item.provider).firstOrNull;
      if (addon == null) throw StateError('The chosen provider is disabled or removed.');
      final streams = await addons.streams(addon, 'movie', item.id);
      if (!mounted || token != _generation) return;
      _addon = addon;
      final match = item.match(streams);
      if (match != null) {
        await _play(item, addon, match);
      } else {
        setState(() {
          _choices = streams.where((s) => s.externalUrl == null && (s.url != null || s.infoHash != null)).toList();
          _error = 'The chosen source changed or is unavailable. Choose another source to continue.';
        });
      }
    } catch (_) {
      if (mounted && token == _generation) setState(() => _error = 'Could not load this movie’s source. Retry or choose another source.');
    } finally {
      if (mounted && token == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _play(QueuedMovie item, Addon addon, AddonStream stream) async {
    if (widget.picking) {
      Navigator.pop<MovieChoice>(context, (item: item, addon: addon, stream: stream));
      return;
    }
    await play(context, stream, moviePlayback(item), addon: addon, start: item.start, queued: item);
  }

  @override
  void dispose() { _generation++; _back.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.tv ? FlickTokens.background : FlickTokens.surface1,
    body: SafeArea(child: FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
      child: ListenableBuilder(listenable: movieQueue, builder: (context, _) => Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Row(children: [
          QueueIconButton(tooltip: 'Back', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back),
            focusNode: _back, autofocus: context.tv),
          Expanded(child: Text('Playback queue', style: FlickText.railHeading)),
          if (movieQueue.items.isNotEmpty) QueueTextButton(onPressed: () => setState(() => _clear = !_clear), child: const Text('Clear')),
        ])),
        Expanded(child: ListView(
        primary: true,
        padding: EdgeInsets.all(context.tv ? FlickTv.insetV : FlickTokens.pageGutter),
        children: [
          if (_clear) Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Clear the movie queue?'),
            QueueTextButton(onPressed: () { movieQueue.clear(); setState(() => _clear = false); _restoreFocus(); }, child: const Text('Clear all')),
            QueueTextButton(onPressed: () => setState(() => _clear = false), child: const Text('Cancel'))]),
          if (movieQueue.error != null) ...[
            Text(movieQueue.error!, style: FlickText.body),
            QueueTextButton(onPressed: movieQueue.save, child: const Text('Retry saving queue'))],
          if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Skeleton(height: 76, width: double.infinity)),
          if (_error != null) ...[
            Semantics(liveRegion: true, child: Text(_error!, style: FlickText.body)),
            Wrap(spacing: 8, children: [
              QueueTextButton(onPressed: _busy ? null : () => _resolve(_selected!), child: const Text('Retry')),
              QueueTextButton(onPressed: _busy ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) =>
                TitleScreen((id: _selected!.id, type: 'movie', name: _selected!.title, poster: _selected!.poster, scope: _selected!.scope, releaseInfo: null)))),
                child: const Text('Choose another source')),
            ]),
          ],
          if (_choices != null) ...[
            if (_choices!.isEmpty) const Text('No playable sources are available from this provider.'),
            for (final s in _choices!) QueueTextButton(onPressed: _busy ? null : () async {
              setState(() => _busy = true);
              try { await _play(_selected!, _addon!, s); }
              finally { if (mounted) setState(() => _busy = false); }
            }, child: Text([s.name, s.title, s.filename].whereType<String>().join(' · '))),
          ],
          if (movieQueue.items.isEmpty && !_busy) const Padding(padding: EdgeInsets.all(16),
            child: Text('Your movie queue is empty. Add movies beside their playback sources.')),
          for (final (i, item) in movieQueue.items.indexed) RevealArea(child: Padding(
            key: ObjectKey(item), padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${i + 1}. ${item.title}', style: context.tv ? FlickTv.body : FlickText.button),
              Text(item.name ?? item.filename ?? 'Selected source', style: FlickText.metadata),
              Wrap(spacing: 4, children: [
                QueueTextButton(onPressed: _busy ? null : () => _resolve(item), child: const Text('Play next')),
                QueueIconButton(tooltip: 'Move up ${item.title}', onPressed: i == 0 || _busy ? null : () { movieQueue.move(item, -1); _restoreFocus(); }, icon: const Icon(Icons.arrow_upward)),
                QueueIconButton(tooltip: 'Move down ${item.title}', onPressed: i == movieQueue.items.length - 1 || _busy ? null : () { movieQueue.move(item, 1); _restoreFocus(); }, icon: const Icon(Icons.arrow_downward)),
                QueueIconButton(tooltip: 'Remove ${item.title}', onPressed: _busy ? null : () { movieQueue.remove(item); _restoreFocus(); }, icon: const Icon(Icons.close)),
              ]),
            ]),
          )),
        ],
      )),
      ])),
    )),
  );
}
