import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' show ClientException;

import '../addons.dart';
import '../playback.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Row text for a stream. Tests swap it, since describe() belongs to the addons contract.
@visibleForTesting
StreamInfo Function(AddonStream) describeStream = describe;

const _muted = TextStyle(color: FlickTokens.textSecondary);
final _glass = FlickTokens.background.withValues(alpha: 0.45);
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';
bool _offline(Object e) => e is SocketException || e is ClientException;
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
  Future<Meta> _load() => addons.meta(widget.preview.type, widget.preview.id);
  void _retry() => setState(() => _meta = _load());

  @override
  Widget build(BuildContext context) {
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
            TextButton(
              style: TextButton.styleFrom(backgroundColor: _glass),
              onPressed: () => _openSources(context),
              child: const Text('Sources'),
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
              tag: p.id,
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
            offline ? "You're offline." : "Couldn't load this title.",
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
        _StreamList((title: m.name, subtitle: null, type: m.type, videoId: m.id, season: null, episode: null)),
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
    if (seasons.length > 1 && seasons.first == 0) seasons.add(seasons.removeAt(0));
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

/// D3 Streams for one episode.
class StreamsScreen extends StatelessWidget {
  const StreamsScreen(this.meta, this.video, {super.key});
  final Meta meta;
  final Video video;

  @override
  Widget build(BuildContext context) {
    final ep = 'S${video.season ?? 0} E${video.episode ?? 0}';
    return Scaffold(
      appBar: AppBar(title: const Text('Streams'), actions: [
        TextButton(onPressed: () => _openSources(context), child: const Text('Sources')),
        const SizedBox(width: 8),
      ]),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${meta.name} · $ep', style: FlickText.metadata.merge(_muted)),
              if (video.title.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(video.title, style: FlickText.railHeading),
              ],
            ]),
          ),
        ),
        _StreamList((
          title: meta.name,
          subtitle: video.title.isEmpty ? ep : '$ep · ${video.title}',
          type: meta.type,
          videoId: video.id,
          season: video.season,
          episode: video.episode,
        )),
        SliverPadding(padding: EdgeInsets.only(bottom: 28 + MediaQuery.paddingOf(context).bottom)),
      ]),
    );
  }
}

/// Every stream source asked in parallel, one group each; external services gather under "Where to watch".
class _StreamList extends StatefulWidget {
  const _StreamList(this.playback);
  final Playback playback;

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
  Widget build(BuildContext context) => SliverList.list(children: _children());

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
    return [
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
              style: FlickText.metadata.merge(_muted)),
        ),
        for (final (_, s) in services) _ServiceRow(s, widget.playback, key: ValueKey(s.externalUrl)),
      ],
    ];
  }

  List<Widget> _group(Addon a) {
    final r = _results[a.id];
    if (r is List<AddonStream>) {
      final rows = [for (final s in r) if (s.externalUrl == null) _StreamRow(s, widget.playback)];
      // A services-only answer lives under "Where to watch" and must not read as streams found.
      if (rows.isEmpty && r.isNotEmpty) return const [];
      return [
        _Heading(a.name),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Nothing found', style: FlickText.metadata.merge(_muted)),
          ),
        ...rows,
      ];
    }
    return [
      _Heading(a.name),
      if (r == null)
        for (var i = 0; i < 2; i++) const _RowSkeleton()
      else
        _Notice(
          _offline(r) ? Icons.wifi_off : Icons.warning_amber_rounded,
          _offline(r) ? "You're offline" : "${a.name} didn't answer",
          live: true,
          actions: [TextButton(onPressed: () => setState(() => _ask(a)), child: const Text('Retry'))],
        ),
    ];
  }
}

class _StreamRow extends StatelessWidget {
  const _StreamRow(this.stream, this.playback);
  final AddonStream stream;
  final Playback playback;

  @override
  Widget build(BuildContext context) {
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
          TextSpan(text: ' ${seeders ?? '—'}', style: streamMonoStyle.copyWith(color: tint)),
        ],
      if (i.size != null) [TextSpan(text: i.size, style: streamMonoStyle)],
      if (i.origin != null) [TextSpan(text: i.origin)],
    ];
    return _Press(
      label: [
        i.quality,
        release,
        if (seeders != null) '$seeders seeders',
        ?i.size,
        if (i.origin != null) 'from ${i.origin}',
      ].join(', '),
      onTap: () async {
        HapticFeedback.lightImpact();
        await play(context, stream, playback);
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: FlickTokens.outline))),
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
              Text(release, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlickText.body),
              for (final l in i.lines.skip(1)) Text(l, style: FlickText.metadata.merge(_muted)),
              if (telemetry.isNotEmpty)
                Text.rich(TextSpan(style: FlickText.metadata.merge(_muted), children: [
                  for (final (n, part) in telemetry.indexed) ...[if (n > 0) const TextSpan(text: ' · '), ...part],
                ])),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A "where to watch" offer (externalUrl): opens the service's app or site.
class _ServiceRow extends StatefulWidget {
  const _ServiceRow(this.stream, this.playback, {super.key});
  final AddonStream stream;
  final Playback playback;

  @override
  State<_ServiceRow> createState() => _ServiceRowState();
}

class _ServiceRowState extends State<_ServiceRow> {
  var _failed = false;

  Future<void> _open() async {
    HapticFeedback.lightImpact();
    setState(() => _failed = false);
    try {
      await play(context, widget.stream, widget.playback);
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
                Text(name, style: FlickText.cardTitle),
                if (offer != null) Text(offer, style: FlickText.metadata.merge(_muted)),
              ]),
            ),
          ]),
        ),
      ),
      if (_failed)
        _Notice(Icons.report_outlined, "Couldn't open $name",
            live: true, actions: [TextButton(onPressed: _open, child: const Text('Try again'))]),
    ]);
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow(this.meta, this.video);
  final Meta meta;
  final Video video;

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
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => StreamsScreen(meta, v))),
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
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: FlickText.body),
              if (date != null) Text(date, style: FlickText.metadata.merge(_muted)),
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
  Widget build(BuildContext context) => Semantics(
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
  Widget build(BuildContext context) => SizedBox(
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
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Semantics(header: true, child: Text(text, style: style)),
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
                Text(text, style: FlickText.body),
                if (detail != null) Text(detail!, style: FlickText.metadata.merge(_muted)),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
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
