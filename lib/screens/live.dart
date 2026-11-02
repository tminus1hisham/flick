import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kit/focus.dart';
import '../live.dart';
import '../playback.dart';
import '../theme.dart';
import '../widgets.dart';
import 'discover.dart';

class LiveTab extends StatefulWidget {
  const LiveTab({this.active = true, this.client, super.key});
  final bool active;
  final LiveClient? client;
  @override
  State<LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<LiveTab> {
  late final _client = widget.client ?? LiveClient();
  final _search = TextEditingController();
  late final _searchFocus = FocusNode(onKeyEvent: (node, event) {
    if (context.tv && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
      node.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });
  int _sport = 1, _generation = 0;
  bool _loaded = false, _busy = false;
  List<LiveEvent> _events = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(LiveTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_loaded) _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    setState(() {});
  }

  Future<void> _load() async {
    final token = ++_generation;
    setState(() { _loaded = true; _busy = true; _error = null; _events = []; });
    try {
      final events = await _client.events(_sport);
      if (mounted && token == _generation) setState(() => _events = events);
    } catch (e) {
      if (mounted && token == _generation) setState(() => _error = liveError(e));
    } finally {
      if (mounted && token == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final events = _events.where((event) =>
      event.name.toLowerCase().contains(query) || event.league.toLowerCase().contains(query)).toList();
    final header = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Live', style: context.tv ? FlickTv.page : FlickText.detailTitle)),
        IconButton(tooltip: 'Refresh events', onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 8),
      SingleChildScrollView(scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: context.tv ? 6 : 0),
        child: Row(children: [for (final sport in liveSports.entries) Padding(
          padding: const EdgeInsets.only(right: 8),
          child: context.tv ? InitialFocus(child: TvChoice(sport.value, selected: _sport == sport.key,
            onActivate: () { if (_sport != sport.key) { _sport = sport.key; _load(); } }))
            : ChoiceChip(label: Text(sport.value), selected: _sport == sport.key,
              onSelected: (_) { if (_sport != sport.key) { _sport = sport.key; _load(); } }),
        )]),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        focusNode: _searchFocus,
        style: context.tv ? FlickTv.body : FlickText.body,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) { if (context.tv) _searchFocus.focusInDirection(TraversalDirection.down); },
        decoration: InputDecoration(
          labelText: 'Search games',
          hintText: 'Team, game or league',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _search.text.isEmpty ? null : IconButton(
            tooltip: 'Clear search', onPressed: _clearSearch, icon: const Icon(Icons.close)),
        ),
      ),
      const SizedBox(height: 12),
    ]);
    return Material(color: FlickTokens.background, child: SafeArea(bottom: false,
      child: FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
        child: Padding(padding: EdgeInsets.fromLTRB(
          context.tv ? FlickTv.gridPad : FlickTokens.pageGutter, context.tv ? FlickTv.insetV : 8,
          context.tv ? FlickTv.gridPad : FlickTokens.pageGutter, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            header,
            Expanded(child: _busy ? ListView(children: [for (var i = 0; i < 5; i++)
              const Padding(padding: EdgeInsets.only(bottom: 12), child: Skeleton(width: double.infinity, height: 76))])
              : _error != null ? _LiveNotice(_error!, retry: _load)
              : _events.isEmpty ? _LiveNotice('No events for ${liveSports[_sport]}.', retry: _load)
              : events.isEmpty ? _LiveNotice('No games match your search.', retry: _clearSearch, actionLabel: 'Clear search')
              : ListView.separated(
                itemCount: events.length, separatorBuilder: (_, _) => const SizedBox(height: 8),
                padding: EdgeInsets.fromLTRB(context.tv ? 6 : 0, 6, context.tv ? 6 : 0, 24),
                itemBuilder: (_, i) {
                  final event = events[i];
                  return _LiveRow(title: event.name, detail: [event.league, _eventTime(event)].where((s) => s.isNotEmpty).join(' · '),
                    onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _Channels(event, _client))));
                },
              )),
          ]),
        ),
      ),
    ));
  }
}

String _eventTime(LiveEvent event) {
  final d = event.start;
  final time = '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final status = switch (event.status) {
    >= 10 && < 10000 => 'Live',
    10000 => 'Ended',
    10001 => 'Cancelled',
    10002 => 'Interrupted',
    10101 => 'Time to be confirmed',
    10102 => 'Suspended',
    10103 => 'Postponed',
    _ => '',
  };
  return status.isEmpty ? time : '$status · $time';
}

class _Channels extends StatefulWidget {
  const _Channels(this.event, this.client);
  final LiveEvent event;
  final LiveClient client;
  @override
  State<_Channels> createState() => _ChannelsState();
}

class _ChannelsState extends State<_Channels> {
  List<LiveChannel> _channels = [];
  bool _busy = true;
  int? _resolving;
  String? _error, _notice;
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _busy = true; _error = null; });
    try {
      final channels = await widget.client.channels(widget.event);
      if (mounted) setState(() => _channels = channels);
    } catch (e) {
      if (mounted) setState(() => _error = liveError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play(LiveChannel channel) async {
    if (_resolving != null) return;
    setState(() { _resolving = channel.id; _notice = null; });
    try {
      final source = await widget.client.resolve(channel);
      if (!mounted) return;
      await playLive(context, '${widget.event.name} · ${channel.name}', source, () => widget.client.resolve(channel),
        event: widget.event, channel: channel, client: widget.client);
    } catch (e) {
      if (mounted) setState(() => _notice = liveError(e));
    } finally {
      try { await widget.client.stop(); } catch (_) {}
      if (mounted) setState(() => _resolving = null);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.event.name)),
    body: FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
      child: _busy ? const Padding(padding: EdgeInsets.all(24), child: Skeleton(width: double.infinity, height: 76))
        : _error != null ? _LiveNotice(_error!, retry: _load)
        : _channels.isEmpty ? _LiveNotice('No channels are available for this event yet.', retry: _load)
        : ListView(padding: EdgeInsets.all(context.tv ? FlickTv.insetV : FlickTokens.pageGutter), children: [
          if (_notice != null) Padding(padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(liveRegion: true, child: Text(_notice!, style: FlickText.body))),
          for (final (i, channel) in _channels.indexed) Padding(padding: const EdgeInsets.only(bottom: 8),
            child: InitialFocus(child: _LiveRow(title: channel.name,
              detail: !channel.available ? 'Unavailable' : _resolving == channel.id ? 'Opening live stream…' : 'Watch live',
              onTap: channel.available ? () => _play(channel) : null, autofocus: i == 0))),
        ]),
    ),
  );
}

class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.title, required this.detail, required this.onTap, this.autofocus = false});
  final String title, detail;
  final VoidCallback? onTap;
  final bool autofocus;
  @override
  Widget build(BuildContext context) => RevealArea(child: FocusFrame.button(
    semanticLabel: '$title, $detail', onActivate: onTap, autofocus: context.tv && autofocus,
    child: Container(constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: FlickTokens.surface1, borderRadius: BorderRadius.circular(FlickTokens.controlRadius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: context.tv ? FlickTv.body : FlickText.button),
        const SizedBox(height: 4),
        Text(detail, style: context.tv ? FlickTv.meta : FlickText.metadata),
      ])),
  ));
}

class _LiveNotice extends StatelessWidget {
  const _LiveNotice(this.message, {required this.retry, this.actionLabel = 'Try again'});
  final String message, actionLabel;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(liveRegion: true, child: Text(message, style: context.tv ? FlickTv.body : FlickText.body)),
      const SizedBox(height: 16),
      InitialFocus(child: TextButton(onPressed: retry, child: Text(actionLabel))),
    ]),
  ));
}
