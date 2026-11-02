
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../addons.dart';
import '../history.dart';
import '../downloads.dart' show DownloadState;
import '../kit/download_button.dart';
import '../kit/toggle.dart';
import '../kit/focus.dart';
import '../kit/queue_controls.dart';
import '../playback.dart';
import '../queue.dart';
import '../player_keys.dart' show playerTime;
import '../state.dart';
import '../theme.dart';
import '../upnext.dart';
import '../widgets.dart';
import 'torrent.dart';
import 'discover.dart' show TvChoice;

/// Row text for a stream. Tests swap it, since describe() belongs to the addons contract.
@visibleForTesting
StreamInfo Function(AddonStream) describeStream = describe;

const _muted = TextStyle(color: FlickTokens.textSecondary);
final _glass = FlickTokens.background.withValues(alpha: 0.45);
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';
// The client can't tell offline from an addon being down: both are AddonError.unreachable.
bool _offline(Object e) => e is AddonException && e.kind == AddonError.unreachable;
void _openSources(BuildContext context) => Navigator.pushNamed(context, '/sources');

/// D2 Title: a movie's streams inline, or a series' seasons and episodes (an episode opens [StreamsScreen]).
class TitleScreen extends StatefulWidget {
  const TitleScreen(this.preview, {super.key});

  /// What Discover already knows, shown while the full meta loads; its poster is the Hero (tag = id).
  final MetaPreview preview;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  late Future<Meta> _meta = _load();
  int? _season;

  bool get _series => widget.preview.type == 'series';
  Future<Meta> _load() => addons.scopedMeta(widget.preview.type, widget.preview.id, widget.preview.scope);
  void _retry() => setState(() { _meta = _load(); });

  @override
  Widget build(BuildContext context) {
    if (context.tv) { return _TvTitleScreen(widget.preview); }
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(children: [
        FutureBuilder<Meta>(
          future: _meta,
          builder: (context, s) => CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _hero(s.data, loading: !s.hasData && !s.hasError)),
            ..._body(s),
            SliverPadding(padding: EdgeInsets.only(bottom: 28 + MediaQuery.paddingOf(context).bottom)),
          ]),
        ),
        // Pinned so the way back stays reachable once the artwork scrolls away.
        Positioned(
          top: top + 4,
          left: 8,
          right: 8,
          child: Row(children: [
            BackButton(style: IconButton.styleFrom(backgroundColor: _glass)),
            const Spacer(),
            IconButton(
              tooltip: 'Sources',
              style: IconButton.styleFrom(backgroundColor: _glass),
              onPressed: () => _openSources(context),
              icon: const Icon(Icons.settings_outlined),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _hero(Meta? m, {required bool loading}) {
    final p = widget.preview;
    final backdrop = m?.background ?? m?.poster ?? p.poster;
    final poster = p.poster ?? m?.poster;
    final facts = [?(m?.releaseInfo ?? p.releaseInfo), if (_series) 'Series' else ?m?.runtime];
    final meta = FlickText.metadata.merge(_muted);
    return Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(child: backdrop == null ? const SizedBox() : NetImage(backdrop, icon: false)),
      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: context.flick.scrimTop))),
      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: context.flick.scrimBottom))),
      Padding(
        padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 68, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Hero(
              tag: previewKey(p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
                child: SizedBox(
                  width: 80,
                  height: 120,
                  child: poster == null ? const Skeleton(radius: 0) : NetImage(poster),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m?.name ?? p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlickText.detailTitle),
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(facts.join(' · '), style: meta),
                ],
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          if (loading) ...[
            const Skeleton(width: 160, height: 12, radius: 4),
            const SizedBox(height: 12),
            const Skeleton(height: 14, radius: 4),
            const SizedBox(height: 6),
            const Skeleton(width: 200, height: 14, radius: 4),
          ] else if (m != null) ...[
            if (m.genres.isNotEmpty) Text(m.genres.join(' · '), style: meta),
            if ((m.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(m.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlickText.body),
            ],
          ],
          // Outside the loading branch: the preview is enough to save while the meta loads.
          const SizedBox(height: FlickTokens.grid * 4),
          _Saving(p),
          const SizedBox(height: FlickTokens.grid),
        ]),
      ),
    ]);
  }

  List<Widget> _body(AsyncSnapshot<Meta> s) {
    if (s.hasError) {
      final offline = _offline(s.error!);
      return [
        SliverToBoxAdapter(
          child: _Notice(
            offline ? Icons.wifi_off : Icons.report_outlined,
            offline ? "Couldn't connect. Check your connection and try again." : "Couldn't load this title.",
            live: true,
            actions: [OutlinedButton(onPressed: _retry, child: const Text('Try again'))],
          ),
        ),
      ];
    }
    final m = s.data;
    if (m == null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(children: [
              for (var i = 0; i < 3; i++) _series ? const _EpisodeSkeleton() : const _RowSkeleton(),
            ]),
          ),
        ),
      ];
    }
    if (!_series) {
      return [
        const SliverToBoxAdapter(child: _Heading('Streams', style: FlickText.railHeading)),
        _StreamList(
            (title: m.name, subtitle: null, logo: m.logo, poster: m.poster ?? widget.preview.poster,
                type: m.type, videoId: m.id, season: null, episode: null, scope: videoScope(m.id, m.scope), meta: null),
            poster: m.poster ?? widget.preview.poster),
      ];
    }
    if (m.videos.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _Notice(Icons.video_library_outlined, 'No episodes listed yet',
              actions: [OutlinedButton(onPressed: _retry, child: const Text('Refresh'))]),
        ),
      ];
    }
    final seasons = {for (final v in m.videos) v.season ?? 0}.toList()..sort();
    // Specials (season 0) go last, as in Stremio.
    if (seasons.length > 1 && seasons.first == 0) { seasons.add(seasons.removeAt(0)); }
    final season = seasons.contains(_season) ? _season! : seasons.first;
    final eps = [for (final v in m.videos) if ((v.season ?? 0) == season) v]
      ..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
    return [
      SliverToBoxAdapter(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Heading('Episodes', style: FlickText.railHeading),
          _Chips([for (final n in seasons) (n, n == 0 ? 'Specials' : 'S$n')], season,
              (n) => setState(() => _season = n)),
        ]),
      ),
      SliverList.list(children: [for (final v in eps) _EpisodeRow(m, v)]),
    ];
  }
}


/// TV keeps the title's identity fixed while episodes and streams share the right pane.
class _TvTitleScreen extends StatefulWidget {
  const _TvTitleScreen(this.preview, {this.meta, this.video});
  final MetaPreview preview;
  final Meta? meta;
  final Video? video;

  @override
  State<_TvTitleScreen> createState() => _TvTitleScreenState();
}

class _TvTitleScreenState extends State<_TvTitleScreen> {
  late Future<Meta> _meta = widget.meta == null
      ? addons.scopedMeta(widget.preview.type, widget.preview.id, widget.preview.scope) : Future.value(widget.meta!);
  late Video? _video = widget.video;
  int? _season;
  final _episodes = GlobalKey<_TvPaneFocusState>();

  void _retry() => setState(() { _meta = addons.scopedMeta(widget.preview.type, widget.preview.id, widget.preview.scope); });

  void _backToEpisodes() {
    setState(() => _video = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => _episodes.currentState?.enter());
  }

  Widget _facts(Meta? meta, BoxConstraints box) {
    final p = widget.preview;
    final art = meta?.background ?? meta?.poster ?? p.poster;
    final facts = [?(meta?.releaseInfo ?? p.releaseInfo), ?meta?.runtime, ...?meta?.genres];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
        child: SizedBox(width: FlickTv.artPane, height: (box.maxHeight * 0.3).clamp(100, FlickTv.artPane * 9 / 16),
          child: art == null ? const Skeleton(radius: 0) : NetImage(art)),
      ),
      const SizedBox(height: 16),
      Text(meta?.name ?? p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlickTv.title),
      const SizedBox(height: 8),
      Text(facts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: FlickTv.meta.merge(_muted)),
      const SizedBox(height: 12),
      Expanded(child: LayoutBuilder(builder: (context, space) {
        final line = MediaQuery.textScalerOf(context).scale(FlickTv.body.fontSize!) * FlickTv.body.height!;
        final lines = (space.maxHeight / line).floor().clamp(1, MediaQuery.sizeOf(context).height < 520 ? 2 : 4);
        return Align(alignment: Alignment.topLeft,
          child: Text(meta?.description ?? '', maxLines: lines, overflow: TextOverflow.ellipsis, style: FlickTv.body));
      })),
      const SizedBox(height: 12),
      _Saving(p),
    ]);
  }

  Widget _pane(List<Widget> slivers, {Key? key}) => _TvPaneFocus(
    key: key,
    child: CustomScrollView(
      cacheExtent: MediaQuery.sizeOf(context).height,
      slivers: [...slivers, const SliverToBoxAdapter(child: SizedBox(height: FlickTv.insetV))],
    ),
  );

  Widget _streams(Meta meta, Video? video) => _pane([
    SliverToBoxAdapter(child: Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (video != null) ...[
          FocusFrame.button(onActivate: _backToEpisodes,
            child: Padding(padding: const EdgeInsets.all(12), child: Text('Back to episodes', style: FlickTv.body))),
          const SizedBox(height: 12),
        ],
        Text('Streams', style: FlickTv.railHeading),
        if (video != null) Text('${episodeLabel(video.season, video.episode)} · ${video.title}',
          style: FlickTv.meta.merge(_muted)),
      ]),
    )),
    _StreamList(video == null
        ? (title: meta.name, subtitle: null, logo: meta.logo, poster: meta.poster ?? widget.preview.poster, type: meta.type, videoId: meta.id, season: null, episode: null, scope: videoScope(meta.id, meta.scope), meta: null)
        : episodePlayback(meta, video), poster: meta.poster ?? widget.preview.poster),
  ], key: ValueKey(video?.id ?? meta.id));

  Widget _right(AsyncSnapshot<Meta> snapshot) {
    if (snapshot.hasError) { return _pane([
      SliverToBoxAdapter(child: InitialFocus(child: _Notice(
        _offline(snapshot.error!) ? Icons.wifi_off : Icons.report_outlined,
        _offline(snapshot.error!) ? "Couldn't connect. Check your connection and try again." : "Couldn't load this title.",
        live: true, actions: [OutlinedButton(onPressed: _retry, child: const Text('Try again'))],
      ))),
    ]); }
    final meta = snapshot.data;
    if (meta == null) { return _pane([
      const SliverToBoxAdapter(child: InitialFocus(child: FocusFrame(
        semanticLabel: 'Loading title', child: _EpisodeSkeleton(),
      ))),
      const SliverToBoxAdapter(child: _EpisodeSkeleton()),
      const SliverToBoxAdapter(child: _EpisodeSkeleton()),
    ]); }
    if (meta.type != 'series') { return _streams(meta, null); }
    final seasons = {for (final v in meta.videos) v.season ?? 0}.toList()..sort();
    if (seasons.length > 1 && seasons.first == 0) { seasons.add(seasons.removeAt(0)); }
    final season = seasons.contains(_season) ? _season : seasons.firstOrNull;
    final episodes = [for (final v in meta.videos) if ((v.season ?? 0) == season) v]
      ..sort((a, b) => (a.episode ?? 0).compareTo(b.episode ?? 0));
    return IndexedStack(index: _video == null ? 0 : 1, children: [
      _pane([
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.only(left: 10),
          child: Text('Episodes', style: FlickTv.railHeading))),
        if (seasons.isNotEmpty) SliverToBoxAdapter(child: InitialFocus(child: RevealArea(
          child: _Chips([for (final n in seasons) (n, n == 0 ? 'Specials' : 'S$n')], season,
            (n) => setState(() => _season = n)),
        ))),
        if (episodes.isEmpty) SliverToBoxAdapter(child: InitialFocus(child: _Notice(
          Icons.video_library_outlined, 'No episodes listed yet',
          actions: [OutlinedButton(onPressed: _retry, child: const Text('Refresh'))],
        ))),
        SliverList.list(children: [for (final video in episodes)
          Padding(padding: const EdgeInsets.all(FlickTv.gridPad),
            child: RevealArea(child: _EpisodeRow(meta, video,
              onSelect: () => setState(() => _video = video)))),
        ]),
      ], key: _episodes),
      if (_video != null) _streams(meta, _video),
    ]);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _video == null,
    onPopInvokedWithResult: (didPop, _) { if (!didPop && _video != null) _backToEpisodes(); },
    child: Scaffold(body: FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(FlickTv.railColumn + FlickTv.contentGap, FlickTv.insetV,
            FlickTv.insetH, FlickTv.insetV),
          child: FutureBuilder<Meta>(future: _meta, builder: (context, snapshot) => LayoutBuilder(
            builder: (context, box) => Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: FlickTv.artPane, child: _facts(snapshot.data, box)),
              const SizedBox(width: FlickTv.paneGap),
              Expanded(child: _right(snapshot)),
            ]),
          )),
        ),
        Positioned(left: FlickTv.insetH + 12, top: FlickTv.insetV,
          child: _TvTitleAction(Icons.arrow_back, 'Back',
            () => _video != null ? _backToEpisodes() : Navigator.maybePop(context))),
        Positioned(left: FlickTv.insetH + 12, bottom: FlickTv.insetV,
          child: _TvTitleAction(Icons.settings_outlined, 'Sources', () => _openSources(context))),
      ]),
    )),
  );
}

class _TvTitleAction extends StatelessWidget {
  const _TvTitleAction(this.icon, this.label, this.onActivate, {this.selected});
  final IconData icon;
  final String label;
  final VoidCallback? onActivate;
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(toggled: selected, child: FocusFrame.button(
    semanticLabel: label, onActivate: onActivate,
    child: SizedBox.square(dimension: FlickTokens.minTouchTarget,
      child: Icon(icon, color: selected == true ? FlickTokens.accent : FlickTokens.textPrimary)),
  ));
}

/// A loading slot hands focus to its replacement only while this pane still owns focus.
class _TvPaneFocus extends StatefulWidget {
  const _TvPaneFocus({required this.child, this.autofocus = true, super.key});
  final Widget child;
  final bool autofocus;
  @override
  State<_TvPaneFocus> createState() => _TvPaneFocusState();
}

class _TvPaneFocusState extends State<_TvPaneFocus> {
  final _scope = FocusScopeNode(debugLabel: 'Title pane',
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope);
  void enter() => enterScope(_scope);
  void _changed() {
    if (_scope.hasPrimaryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scope.hasPrimaryFocus) { enter(); }
      });
    }
  }
  @override
  void initState() {
    super.initState();
    _scope.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.autofocus && primaryFocus?.context?.findAncestorWidgetOfExactType<_TvTitleAction>() == null) { enter(); }
    });
  }
  @override
  void dispose() {
    _scope.removeListener(_changed);
    _scope.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => FocusScope(node: _scope, includeSemantics: false, child: widget.child);
}

/// Favourite + like for a Discover title, saved on this device.
class _Saving extends StatefulWidget {
  const _Saving(this.preview);
  final MetaPreview preview;
  @override
  State<_Saving> createState() => _SavingState();
}

class _SavingState extends State<_Saving> {
  String? _error;

  Future<bool> _save(Future<void> Function() change) async {
    try {
      await change();
      if (mounted) setState(() => _error = null);
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Try the action again.');
      return false;
    }
  }

  Widget _action(bool on, IconData icon, IconData onIcon, String label, String onLabel, Future<void> Function() change) =>
    context.tv ? _TvTitleAction(on ? onIcon : icon, on ? onLabel : label, () => _save(change), selected: on)
      : ToggleAction(on: on, icon: icon, onIcon: onIcon, label: label, onLabel: onLabel, onPressed: () => _save(change));

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    return ListenableBuilder(listenable: saved, builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _action(saved.isFavourite(p.id, scope: p.scope, type: p.type), Icons.favorite_border_rounded, Icons.favorite_rounded,
            'Add to favourites', 'Remove from favourites', () => saved.toggleFavourite(p)),
          _action(saved.isLiked(p.id), Icons.thumb_up_outlined, Icons.thumb_up_rounded,
            'Like title', 'Unlike title', () => saved.toggleLike(p.id)),
          _action(saved.inMyList(p), Icons.playlist_add, Icons.playlist_add_check,
            'Add to My List', 'Remove from My List', () => saved.toggleMyList(p)),
        ]),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!, style: context.tv ? FlickTv.meta : FlickText.body)),
      ]));
  }
}

/// D3 Streams for one episode.
class StreamsScreen extends StatelessWidget {
  const StreamsScreen(this.meta, this.video, {super.key});
  final Meta meta;
  final Video video;

  @override
  Widget build(BuildContext context) {
    if (context.tv) { return _TvTitleScreen(
      (id: meta.id, type: meta.type, name: meta.name, poster: meta.poster, scope: meta.scope, releaseInfo: meta.releaseInfo),
      meta: meta, video: video,
    ); }
    final ep = episodeLabel(video.season, video.episode);
    return Scaffold(
      appBar: AppBar(title: const Text('Streams'), actions: [
        IconButton(tooltip: 'Sources', onPressed: () => _openSources(context), icon: const Icon(Icons.settings_outlined)),
        const SizedBox(width: 8),
      ]),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${meta.name} · $ep', style: (context.tv ? FlickTv.meta : FlickText.metadata).merge(_muted)),
              if (video.title.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(video.title, style: FlickText.railHeading),
              ],
            ]),
          ),
        ),
        _StreamList(episodePlayback(meta, video), poster: meta.poster),
        SliverPadding(padding: EdgeInsets.only(bottom: 28 + MediaQuery.paddingOf(context).bottom)),
      ]),
    );
  }
}

/// Every stream source asked in parallel, one group each; external services gather under "Where to watch".
class _StreamList extends StatefulWidget {
  const _StreamList(this.playback, {this.poster});
  final Playback playback;
  final String? poster;

  @override
  State<_StreamList> createState() => _StreamListState();
}

class _StreamListState extends State<_StreamList> {
  var _sources = <Addon>[];

  /// Addon id → its streams, or the error it failed with; absent while asking.
  final _results = <String, Object>{};

  /// Addon id → the request whose answer is still wanted; a stale answer is dropped.
  final _asking = <String, Object>{};
  String? _filter;
  bool _startOver = false;

  @override
  void initState() {
    super.initState();
    _sync();
    addons.addListener(_changed);
  }

  @override
  void dispose() {
    addons.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(_sync);

  /// Keeps groups for sources still there, asks only the new ones.
  void _sync() {
    final next = addons.streamSources(widget.playback.type, widget.playback.videoId);
    final ids = {for (final a in next) a.id};
    _results.removeWhere((id, _) => !ids.contains(id));
    _asking.removeWhere((id, _) => !ids.contains(id));
    if (!ids.contains(_filter)) _filter = null;
    for (final a in next) {
      if (!_sources.any((o) => o.id == a.id)) _ask(a);
    }
    _sources = next;
  }

  Future<void> _ask(Addon a) async {
    final token = Object();
    _asking[a.id] = token;
    _results.remove(a.id);
    Object r;
    try {
      r = await addons.streams(a, widget.playback.type, widget.playback.videoId);
    } catch (e) {
      r = e;
    }
    if (!mounted || _asking[a.id] != token) return;
    setState(() => _results[a.id] = r);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: history,
    builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final children = _children();
    if (!context.tv) { return SliverList.list(children: children); }
    return SliverMainAxisGroup(slivers: [for (final child in children)
      if (child is _TvPaneFocus)
        SliverPadding(key: child.key, padding: const EdgeInsets.symmetric(horizontal: FlickTv.gridPad, vertical: 6),
          sliver: InitialFocus(child: child))
      else
        SliverToBoxAdapter(child: Padding(key: child.key,
          padding: const EdgeInsets.symmetric(horizontal: FlickTv.gridPad, vertical: 6),
          child: RevealArea(child: child is _Chips<String?> || child is _Heading
              ? child : InitialFocus(child: child)))),
    ]);
  }

  List<Widget> _children() {
    if (_sources.isEmpty) {
      return [
        _Notice(Icons.extension_outlined, 'Install a stream source to find playable links',
            actions: [FilledButton(onPressed: () => _openSources(context), child: const Text('Add a source'))]),
      ];
    }
    final shown = [for (final a in _sources) if (_filter == null || _filter == a.id) a];
    final services = [
      for (final a in shown)
        if (_results[a.id] case final List<AddonStream> l)
          for (final s in l)
            if (s.externalUrl != null) (a, s),
    ];
    // Every source answered with only services (or nothing): say so, and offer a real stream source.
    final noStreams = _sources.every((a) => switch (_results[a.id]) {
          final List<AddonStream> l => l.every((s) => s.externalUrl != null),
          _ => false,
        });
    final noun = widget.playback.type == 'series' ? 'episode' : 'movie';
    final position = history.position(widget.playback.type, widget.playback.videoId, scope: widget.playback.scope);
    return [
      if (position > Duration.zero && !noStreams) ...[
        _Chips([(false, 'Resume · ${playerTime(position)}'), (true, 'Start over')], _startOver,
          (value) => setState(() => _startOver = value)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(_startOver ? 'Choose a source to play from the beginning.' : 'Choose a source to resume.',
            style: context.tv ? FlickTv.meta : FlickText.metadata)),
      ],
      if (_sources.length >= 2)
        _Chips([(null, 'All'), for (final a in _sources) (a.id, a.name)], _filter,
            (id) => setState(() => _filter = id)),
      if (noStreams)
        _Notice(
          Icons.videocam_off_outlined,
          'No streams for this $noun',
          detail: 'Asked ${_sources.map((a) => a.name).join(', ')}',
          actions: [
            OutlinedButton(
              onPressed: () => setState(() => _sources.forEach(_ask)),
              child: const Text('Refresh streams'),
            ),
            FilledButton(onPressed: () => _openSources(context), child: const Text('Add a source')),
          ],
        )
      else
        for (final a in shown) ..._group(a),
      if (services.isNotEmpty) ...[
        const _Heading('Where to watch'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('${{for (final (a, _) in services) a.name}.join(', ')} · Opens another app or website.',
              style: (context.tv ? FlickTv.meta : FlickText.metadata).merge(_muted)),
        ),
        for (final (a, s) in services) _ServiceRow(s, widget.playback, a, key: ValueKey(s.externalUrl)),
      ],
    ];
  }

  List<Widget> _group(Addon a) {
    final r = _results[a.id];
    final List<Widget> children;
    if (r is List<AddonStream>) {
      final rows = [
        for (final s in r)
          if (s.externalUrl == null)
            _StreamRow(s, widget.playback, a, start: _startOver ? Duration.zero : null,
              poster: widget.poster, key: ValueKey((a.id, s))),
      ];
      // A services-only answer lives under "Where to watch" and must not read as streams found.
      if (rows.isEmpty && r.isNotEmpty) { return const []; }
      children = [
        _Heading(a.name),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Nothing found', style: (context.tv ? FlickTv.meta : FlickText.metadata).merge(_muted)),
          ),
        ...rows,
      ];
    } else {
      children = [
        _Heading(a.name),
        if (r == null)
          for (var i = 0; i < 2; i++)
            if (context.tv) const FocusFrame(semanticLabel: 'Loading streams', child: _RowSkeleton())
            else const _RowSkeleton()
        else
          _Notice(
            Icons.warning_amber_rounded,
            "${a.name} didn't answer",
            live: true,
            actions: [TextButton(onPressed: () => setState(() { _ask(a); }), child: const Text('Retry'))],
          ),
      ];
    }
    if (!context.tv) { return children; }
    // Each source retains focus while another source inserts or replaces its rows.
    return [_TvPaneFocus(key: ValueKey(('source', a.id)), autofocus: false,
      child: SliverList.list(children: [
        for (final child in children) Padding(key: child.key, padding: const EdgeInsets.symmetric(vertical: 6),
          child: RevealArea(child: child)),
      ]),
    )];
  }

}

class _StreamRow extends StatefulWidget {
  const _StreamRow(this.stream, this.playback, this.addon, {this.poster, this.start, super.key});
  final AddonStream stream;
  final Playback playback;
  final Addon addon;
  final String? poster;
  final Duration? start;

  @override
  State<_StreamRow> createState() => _StreamRowState();
}

class _StreamRowState extends State<_StreamRow> {
  String? _playbackQueueNotice;
  var _queuing = false;
  var _queued = false;
  var _failed = false;

  Future<void> _download() async {
    if (_queuing || _queued) return;
    setState(() {
      _queuing = true;
      _failed = false;
    });
    try {
      var queued = true;
      final stream = widget.stream;
      final playback = widget.playback;
      if (stream.infoHash != null) {
        queued = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => TorrentScreen(
          magnetFor(stream),
          fileIdx: stream.fileIdx,
          season: playback.season,
          episode: playback.episode,
          title: playback.title,
          playback: playback,
          download: true,
          subtitles: stream.subtitles,
          poster: widget.poster,
        ))) == true;
      } else {
        await downloads.enqueueStream(
          url: stream.url!,
          headers: stream.headers,
          title: playback.title,
          poster: widget.poster,
          playback: playback,
          subtitles: stream.subtitles,
        );
      }
      if (mounted) setState(() => _queued = queued);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _queuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = widget.stream;
    final playback = widget.playback;
    final addon = widget.addon;
    final i = describeStream(stream);
    final release = i.lines.firstOrNull ?? stream.filename ?? stream.name ?? '';
    final seeders = i.seeders;
    final tint = switch (seeders) {
      null => FlickTokens.textSecondary,
      >= 20 => context.flick.success,
      0 => context.flick.warning,
      _ => FlickTokens.textSecondary,
    };
    final telemetry = <List<InlineSpan>>[
      // Seeders only mean something for torrents; unknown is "—", never 0.
      if (stream.infoHash != null)
        [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.person_outline, size: 14, color: tint),
          ),
          TextSpan(text: ' ${seeders ?? '—'}', style: streamMonoStyle.copyWith(color: tint, fontSize: context.tv ? 14 : 12)),
        ],
      if (i.size != null) [TextSpan(text: i.size, style: context.tv ? streamMonoStyle.copyWith(fontSize: 14) : streamMonoStyle)],
      if (i.origin != null) [TextSpan(text: i.origin)],
    ];
    final downloadable = (stream.url != null || stream.infoHash != null) && stream.externalUrl == null;
    final queueAction = playback.type == 'movie' && downloadable
      ? ListenableBuilder(listenable: movieQueue, builder: (context, _) => QueueIconButton(
          tooltip: movieQueue.contains(playback.videoId, provider: addon.base) ? 'Already in playback queue' : 'Add to playback queue',
          onPressed: () async {
            final added = await movieQueue.add(QueuedMovie.fromStream(playback.videoId, playback.title,
              playback.poster ?? widget.poster, addon, stream, start: widget.start, scope: playback.scope));
            if (mounted) {
              setState(() => _playbackQueueNotice = movieQueue.error ??
                (added ? 'Added to playback queue.' : 'Already in playback queue.'));
            }
          }, icon: Icon(movieQueue.contains(playback.videoId, provider: addon.base) ? Icons.playlist_add_check : Icons.playlist_add)))
      : null;
    final downloadLabel = stream.infoHash != null ? 'Download torrent' : 'Download';
    final status = _playbackQueueNotice ?? (_queued ? 'Queued' : _queuing ? 'Queuing…' : _failed ? "Couldn't queue download. Try again." : null);
    if (context.tv) { return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: _Press(
        label: [i.quality, release, if (seeders != null) '$seeders seeders', ?i.size].join(', '),
        onTap: () async => play(context, stream, playback, addon: addon, start: widget.start),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: FlickTokens.surface1,
            borderRadius: BorderRadius.circular(FlickTokens.controlRadius)),
          child: Row(children: [
            const Icon(Icons.play_arrow_rounded, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.quality, style: streamMonoStyle.copyWith(fontSize: 16, height: 22 / 16)),
              Text(release, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlickTv.meta.merge(_muted)),
              if (telemetry.isNotEmpty) Text.rich(TextSpan(style: FlickTv.meta.merge(_muted), children: [
                for (final (n, part) in telemetry.indexed) ...[if (n > 0) const TextSpan(text: ' · '), ...part],
              ])),
              if (status != null) Semantics(liveRegion: true, child: Text(status, style: FlickTv.meta.copyWith(
                color: _failed ? context.flick.danger : FlickTokens.textSecondary))),
            ])),
          ]),
        ),
      )),
      if (downloadable) ...[
        const SizedBox(width: 12),
        _TvTitleAction(_queued ? Icons.check : Icons.download_outlined,
          status ?? downloadLabel, _queuing || _queued ? null : _download),
      ],
      ?queueAction,
    ]); }
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FlickTokens.outline))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _Press(
              label: [
                i.quality,
                release,
                if (seeders != null) '$seeders seeders',
                ?i.size,
                if (i.origin != null) 'from ${i.origin}',
              ].join(', '),
              onTap: () async {
                HapticFeedback.lightImpact();
                await play(context, stream, playback, addon: addon, start: widget.start);
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(children: [
                  SizedBox(
                    width: FlickTokens.streamQualityWidth,
                    child: Container(
                      height: 24,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: FlickTokens.surface2,
                        borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(i.quality, style: FlickText.metadata.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(release, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tv ? FlickTv.body : FlickText.body),
                      for (final l in i.lines.skip(1)) Text(l, style: (context.tv ? FlickTv.meta : FlickText.metadata).merge(_muted)),
                      if (telemetry.isNotEmpty)
                        Text.rich(TextSpan(style: (context.tv ? FlickTv.meta : FlickText.metadata).merge(_muted), children: [
                          for (final (n, part) in telemetry.indexed) ...[if (n > 0) const TextSpan(text: ' · '), ...part],
                        ])),
                    ]),
                  ),
                ]),
              ),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Semantics(
                  liveRegion: true,
                  child: Text(status, style: FlickText.metadata.copyWith(
                    color: _failed ? context.flick.danger : FlickTokens.textSecondary,
                  )),
                ),
              ),
          ]),
        ),
        ?queueAction,
        if (downloadable && stream.infoHash == null)
          Semantics(
            container: true,
            label: downloadLabel,
            button: true,
            enabled: !_queuing && !_queued,
            onTap: _queuing || _queued ? null : _download,
            excludeSemantics: true,
            child: IconButton(
              tooltip: downloadLabel,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(_queued ? Icons.check : Icons.download_outlined),
              onPressed: _queuing || _queued ? null : _download,
            ),
          ),
        if (downloadable && stream.infoHash != null)
          ListenableBuilder(listenable: downloads, builder: (context, _) {
            final hash = stream.infoHash;
            final d = hash == null ? null : downloads.of(hash, stream.fileIdx, playback.videoId);
            final done = d?.state == DownloadState.done;
            final active = d != null && d.state != DownloadState.failed && !done;
            return DownloadButton(
              progress: active ? (d.total > 0 ? (d.bytes / d.total).clamp(0.0, 1.0) : 0) : null,
              done: done,
              label: downloadLabel,
              onPressed: _queuing || _queued || active || done ? null : _download,
            );
          }),
      ]),
    );
  }
}

/// A "where to watch" offer (externalUrl): opens the service's app or site.
class _ServiceRow extends StatefulWidget {
  const _ServiceRow(this.stream, this.playback, this.addon, {super.key});
  final AddonStream stream;
  final Playback playback;
  final Addon addon;

  @override
  State<_ServiceRow> createState() => _ServiceRowState();
}

class _ServiceRowState extends State<_ServiceRow> {
  var _failed = false;
  var _noHandler = false;

  Future<void> _open() async {
    HapticFeedback.lightImpact();
    setState(() => _failed = _noHandler = false);
    try {
      await play(context, widget.stream, widget.playback, addon: widget.addon);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => e.code == 'noHandler' ? _noHandler = true : _failed = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.stream.name ?? 'This service';
    final offer = widget.stream.title;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Press(
        label: '${[name, ?offer].join(', ')}. Opens another app or website.',
        link: true,
        onTap: _open,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FlickTokens.outline))),
          child: Row(children: [
            SizedBox(
              width: FlickTokens.streamQualityWidth,
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: FlickTokens.surface1,
                    borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
                  ),
                  child: const Icon(Icons.open_in_new, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: context.tv ? FlickTv.card : FlickText.cardTitle),
                if (offer != null) Text(offer, style: (context.tv ? FlickTv.meta : FlickText.metadata).merge(_muted)),
              ]),
            ),
          ]),
        ),
      ),
      if (_noHandler)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No browser on this device. Open on your phone:', style: FlickText.body),
            SelectableText(widget.stream.externalUrl!, style: context.tv ? monoStyle : streamMonoStyle),
          ]),
        ),
      if (_failed)
        _Notice(Icons.report_outlined, "Couldn't open $name",
            live: true, actions: [TextButton(onPressed: _open, child: const Text('Try again'))]),
    ]);
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow(this.meta, this.video, {this.onSelect});
  final Meta meta;
  final Video video;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final v = video;
    final released = v.released?.toLocal();
    final future = released != null && released.isAfter(DateTime.now());
    final name = [if (v.episode != null) 'E${v.episode}', if (v.title.isNotEmpty) v.title].join(' · ');
    final date = released == null ? null : (future ? 'Airs ${_day(released)}' : '${_day(released)} ${released.year}');
    return _Press(
      label: [name, ?date].join(', '),
      onTap: future
          ? null
          : onSelect ?? () => Navigator.push(context, MaterialPageRoute(builder: (_) => StreamsScreen(meta, v))),
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
            child: SizedBox(
              width: 96,
              height: 54,
              child: v.thumbnail == null ? const Skeleton(radius: 0) : NetImage(v.thumbnail!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tv ? FlickTv.body : FlickText.body),
              if (date != null) Text(date, style: (context.tv ? FlickTv.meta : FlickText.metadata).merge(_muted)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Scale 0.97 while pressed (not under reduced motion); one semantics node with [label].
class _Press extends StatefulWidget {
  const _Press({required this.label, required this.onTap, required this.child, this.link = false});
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  final bool link;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  var _down = false;

  @override
  Widget build(BuildContext context) => context.tv
      ? FocusFrame.button(
          semanticLabel: widget.label,
          onActivate: widget.onTap,
          child: ExcludeSemantics(child: widget.child),
        )
      : Semantics(
        container: true,
        button: !widget.link,
        link: widget.link,
        enabled: widget.onTap != null,
        label: widget.label,
        onTap: widget.onTap,
        excludeSemantics: true,
        child: AnimatedScale(
          scale: _down && !MediaQuery.disableAnimationsOf(context) ? 0.97 : 1,
          duration: FlickTokens.stateDuration,
          curve: FlickTokens.curveIn,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _down = v),
            child: widget.child,
          ),
        ),
      );
}

/// Horizontal choice chips; a change gives a selection haptic.
class _Chips<T> extends StatelessWidget {
  const _Chips(this.items, this.selected, this.onSelect);
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) => context.tv
      ? SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(FlickTv.gridPad),
          child: Row(children: [for (final (i, item) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            TvChoice(item.$2, selected: item.$1 == selected, onActivate: () => onSelect(item.$1)),
          ]]),
        )
      : SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final (value, label) = items[i];
            return Center(
              child: ChoiceChip(
                label: Text(label),
                selected: value == selected,
                onSelected: (_) {
                  if (value == selected) return;
                  HapticFeedback.selectionClick();
                  onSelect(value);
                },
              ),
            );
          },
        ),
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.style = FlickText.cardTitle});
  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(context.tv ? 10 : 20, 20, context.tv ? 10 : 20, 8),
        child: Semantics(header: true, child: Text(text, style: context.tv ? FlickTv.railHeading : style)),
      );
}

/// Icon + sentence, an optional supporting line and actions; inline, never a popup.
class _Notice extends StatelessWidget {
  const _Notice(this.icon, this.text, {this.detail, this.actions = const [], this.live = false});
  final IconData icon;
  final String text;
  final String? detail;
  final List<Widget> actions;
  final bool live;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: live,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: FlickTokens.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(text, style: context.tv ? FlickTv.body : FlickText.body),
                if (detail != null) Text(detail!, style: (context.tv ? FlickTv.meta : FlickText.metadata).merge(_muted)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: context.tv ? 12 : 8, runSpacing: context.tv ? 12 : 8, children: [for (final action in actions)
                    if (context.tv && action is ButtonStyleButton)
                      FocusFrame.button(
                        onActivate: action.onPressed,
                        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: DefaultTextStyle(style: FlickTv.body, child: action.child ?? const SizedBox())),
                      )
                    else action,
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      );
}

class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(children: [
          Skeleton(width: FlickTokens.streamQualityWidth, height: 24, radius: FlickTokens.controlRadius),
          SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(height: 16, radius: 4),
              SizedBox(height: 4),
              Skeleton(width: 140, height: 12, radius: 4),
            ]),
          ),
        ]),
      );
}

class _EpisodeSkeleton extends StatelessWidget {
  const _EpisodeSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        child: Row(children: [
          Skeleton(width: 96, height: 54),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(width: 160, height: 16, radius: 4),
              SizedBox(height: 8),
              Skeleton(width: 80, height: 12, radius: 4),
            ]),
          ),
        ]),
      );
}
