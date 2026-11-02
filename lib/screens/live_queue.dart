import 'package:flutter/material.dart';

import '../kit/focus.dart';
import '../kit/queue_controls.dart';
import '../live.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class LiveQueuePanel extends StatefulWidget {
  const LiveQueuePanel({required this.client, required this.event, required this.channel,
    required this.onSwitch, super.key});
  final LiveClient client;
  final LiveEvent event;
  final LiveChannel channel;
  final Future<bool> Function(LiveEvent event, LiveChannel channel) onSwitch;
  @override
  State<LiveQueuePanel> createState() => _LiveQueuePanelState();
}

class _LiveQueuePanelState extends State<LiveQueuePanel> {
  final _close = FocusNode(debugLabel: 'Live queue Close');
  void _restoreFocus() { if (context.tv) _close.requestFocus(); }
  late LiveEvent _current = widget.event;
  late LiveChannel _channel = widget.channel;
  late int _sport = widget.event.sport;
  final _search = TextEditingController();
  List<LiveEvent> _events = [];
  List<LiveChannel> _channels = [];
  LiveEvent? _choosing;
  bool _server = false, _loading = false, _switching = false;
  String? _error, _notice;
  int _generation = 0;

  @override
  void initState() { super.initState(); _loadEvents(); }

  Future<void> _loadEvents() async {
    final token = ++_generation;
    setState(() { _loading = true; _error = null; _events = []; _choosing = null; });
    try {
      final events = await widget.client.events(_sport);
      if (mounted && token == _generation) setState(() => _events = events);
    } catch (e) {
      if (mounted && token == _generation) setState(() => _error = liveError(e));
    } finally {
      if (mounted && token == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _loadChannels(LiveEvent event) async {
    final token = ++_generation;
    setState(() { _choosing = event; _loading = true; _error = null; _channels = []; });
    try {
      final channels = await widget.client.channels(event);
      if (mounted && token == _generation) setState(() => _channels = channels);
    } catch (e) {
      if (mounted && token == _generation) setState(() => _error = liveError(e));
    } finally {
      if (mounted && token == _generation) setState(() => _loading = false);
    }
  }

  Future<void> _switch(LiveEvent event, LiveChannel channel) async {
    if (_switching) return;
    setState(() { _switching = true; _error = null; });
    try {
      final ok = await widget.onSwitch(event, channel);
      if (!mounted) return;
      if (ok) {
        liveQueue.remove(event);
        setState(() { _current = event; _channel = channel; _notice = 'Playing ${event.name} · ${channel.name}'; });
      } else {
        setState(() => _error = 'Could not switch this source. Retry or choose another server.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = liveError(e));
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  @override
  void dispose() { _generation++; widget.client.cancelPrepared().catchError((_) {}); _search.dispose(); _close.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final events = _events.where((e) => e.name.toLowerCase().contains(query) || e.league.toLowerCase().contains(query));
    return PopScope(child: FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
      child: ListenableBuilder(listenable: liveQueue, builder: (context, _) => Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Row(children: [
          Expanded(child: Text('Live', style: FlickText.railHeading)),
          QueueIconButton(focusNode: _close, autofocus: context.tv, tooltip: 'Close live queue', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ])),
        if (context.tv) _tabs(),
        Expanded(child: ListView(primary: true, padding: const EdgeInsets.all(16), children: [
          if (!context.tv) _tabs(),
          if (_notice != null) Semantics(liveRegion: true, child: Text(_notice!, style: FlickText.metadata)),
          if (_switching) const Text('Switching live source…', style: FlickText.body),
          if (!_server) ...[
            Text('Queued games', style: FlickText.button),
            if (liveQueue.items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No games queued yet.')),
            if (liveQueue.items.isNotEmpty) QueueTextButton(onPressed: _switching ? null : () => _loadChannels(liveQueue.items.first), child: const Text('Next game')),
            for (final (i, event) in liveQueue.items.indexed) RevealArea(child: Column(
              key: ValueKey((event.sport, event.id)), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                QueueTextButton(onPressed: _switching ? null : () => _loadChannels(event), child: Text('${i + 1}. ${event.name}')),
                Wrap(children: [
                  QueueIconButton(tooltip: 'Move up ${event.name}', onPressed: i == 0 || _switching ? null : () { liveQueue.move(event, -1); _restoreFocus(); }, icon: const Icon(Icons.arrow_upward)),
                  QueueIconButton(tooltip: 'Move down ${event.name}', onPressed: i == liveQueue.items.length - 1 || _switching ? null : () { liveQueue.move(event, 1); _restoreFocus(); }, icon: const Icon(Icons.arrow_downward)),
                  QueueIconButton(tooltip: 'Remove ${event.name}', onPressed: _switching ? null : () { liveQueue.remove(event); _restoreFocus(); }, icon: const Icon(Icons.close)),
                ]),
              ])),
          ],
          if (_choosing != null) ...[
            Text(_choosing!.name, style: FlickText.button),
            if (!_loading && _channels.isEmpty && _error == null) const Text('No channels are available for this game yet.'),
            for (final channel in _channels) RevealArea(child: Semantics(
              selected: _current.id == _choosing!.id && _current.sport == _choosing!.sport &&
                _channel.id == channel.id && _channel.site == channel.site,
              child: QueueTextButton(
              onPressed: !channel.available || _switching ? null : () => _switch(_choosing!, channel),
              child: Row(children: [
                Icon(_current.id == _choosing!.id && _current.sport == _choosing!.sport && _channel.id == channel.id && _channel.site == channel.site
                  ? Icons.check : Icons.play_arrow),
                const SizedBox(width: 8), Expanded(child: Text('${channel.name}${channel.available ? '' : ' · Unavailable'}')),
              ])))),
          ],
          if (_loading) ...[for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: 8), child: Skeleton(width: double.infinity, height: 64))],
          if (_error != null) ...[
            Semantics(liveRegion: true, child: Text(_error!, style: FlickText.body)),
            QueueTextButton(onPressed: _switching ? null : () => _choosing == null ? _loadEvents() : _loadChannels(_choosing!), child: const Text('Retry')),
          ],
          if (!_server) ...[
            const SizedBox(height: 16),
            Text('Find another game', style: FlickText.button),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              for (final sport in liveSports.entries) Padding(padding: const EdgeInsets.only(right: 8),
                child: _tab(sport.value, sport.key == _sport, () { _sport = sport.key; _loadEvents(); })),
            ])),
            QueueFocus(child: TextField(controller: _search, onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Search games', hintText: 'Team, game or league'))),
            if (!_loading && events.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('No games match your search.')),
            for (final event in events) RevealArea(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(event.name, style: FlickText.button),
              Text(event.league, style: FlickText.metadata),
              QueueFocus(child: TextButton.icon(onPressed: _switching ? null : () {
                final added = liveQueue.add(event);
                setState(() => _notice = added ? 'Added ${event.name} to queue.' : '${event.name} is already queued.');
              }, icon: Icon(liveQueue.contains(event) ? Icons.check : Icons.playlist_add),
                label: Text(liveQueue.contains(event) ? 'Already queued' : 'Add to queue'))),
            ])),
          ],
        ])),
      ])),
    ));
  }

  Widget _tabs() => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Row(children: [
    Expanded(child: _tab('Queue', !_server, () { setState(() => _server = false); _loadEvents(); })),
    Expanded(child: _tab('Server', _server, () { setState(() => _server = true); _loadChannels(_current); })),
  ]));

  Widget _tab(String label, bool selected, VoidCallback onPressed) => Semantics(selected: selected,
    child: QueueTextButton(onPressed: _switching ? null : onPressed,
      style: TextButton.styleFrom(backgroundColor: selected ? FlickTokens.surface2 : null,
        minimumSize: const Size(48, 48)), child: Text(label)));
}
