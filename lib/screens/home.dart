import 'package:flutter/material.dart';

import '../jellyfin.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'detail.dart';
import 'library.dart';
import 'torrent.dart';

typedef _Home = ({List<Item> views, List<Item> resume, List<List<Item>> latest});

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_Home> _data = _load();
  final _scroll = ScrollController();

  Future<_Home> _load() async {
    final c = session.client!;
    final views = await c.views();
    final (resume, latest) = await (c.resume(), Future.wait(views.map((v) => c.latest(v.id)))).wait;
    return (views: views, resume: resume, latest: latest);
  }

  void _reload() => setState(() => _data = _load());

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 56;
    return Stack(children: [
      RefreshIndicator(
        edgeOffset: top,
        onRefresh: () async {
          _reload();
          await _data;
        },
        child: FutureBuilder<_Home>(
          future: _data,
          builder: (context, s) {
            if (s.hasError) {
              return Padding(
                  padding: EdgeInsets.only(top: top), child: ErrorState(s.error!, onRetry: _reload));
            }
            final d = s.data;
            return d == null ? const _HomeSkeleton() : _content(d, top);
          },
        ),
      ),
      _TopBar(_scroll),
    ]);
  }

  Widget _content(_Home d, double top) {
    final latestIndex = d.latest.indexWhere((l) => l.isNotEmpty);
    final (hero, eyebrow) = d.resume.isNotEmpty
        ? (d.resume.first, 'Continue watching')
        : latestIndex >= 0
            ? (d.latest[latestIndex].first, 'Latest in ${d.views[latestIndex].name}')
            : (null, '');
    const streamLink = Align(alignment: Alignment.centerRight, child: _StreamLink());
    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: hero == null
              ? Padding(
                  padding: EdgeInsets.fromLTRB(20, top + 24, 20, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nothing to watch yet', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('Media you add to your Jellyfin server will show up here.'),
                    const SizedBox(height: 16),
                    streamLink,
                  ]),
                )
              : Column(children: [_Hero(hero, eyebrow, d.views), streamLink]),
        ),
        if (d.resume.length > 1)
          SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SectionHeader('Up next'),
              SizedBox(
                height: 140 + 64 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: d.resume.length - 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _UpNextCard(d.resume[i + 1]),
                ),
              ),
            ]),
          ),
        for (var i = 0; i < d.views.length; i++)
          SliverToBoxAdapter(child: PosterRow('Latest in ${d.views[i].name}', d.latest[i])),
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }
}

/// Transparent over the hero, turning solid over the first 120dp of scroll.
class _TopBar extends StatelessWidget {
  const _TopBar(this.scroll);
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: scroll,
        builder: (context, _) {
          final t = scroll.hasClients ? (scroll.offset / 120).clamp(0.0, 1.0) : 0.0;
          return ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: t),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, right: 8),
                  child: Row(children: [
                    const FlickMark(size: 24, label: null),
                    const SizedBox(width: 8),
                    Text('Flick', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    const ProfileButton(),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

class _Hero extends StatelessWidget {
  const _Hero(this.item, this.eyebrow, this.views);
  final Item item;
  final String eyebrow;
  final List<Item> views;

  @override
  Widget build(BuildContext context) {
    final c = session.client!;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final progress = progressOf(item);
    final meta = [
      if (item.year != null) '${item.year}',
      ?episodeLine(item),
      ?timeLeft(item),
    ];
    final info = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
      ),
      onPressed: () => openItem(context, item),
      icon: const Icon(Icons.info_outline),
      label: const Text('More info'),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 440),
      // passthrough hands the 440dp minimum to the column so spaceBetween pins the copy to the bottom.
      child: Stack(fit: StackFit.passthrough, children: [
        Positioned.fill(
          child: NetImage(c.backdropUrl(item.seriesId ?? item.id),
              fallback: c.imageUrl(item.id), icon: false),
        ),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: context.flick.scrimTop))),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: context.flick.scrimBottom))),
        Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 56),
              child: SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: views.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Center(
                    child: ActionChip(
                      label: Text(views[i].name),
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => LibraryGrid(view: views[i]))),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(eyebrow, style: text.labelSmall),
                const SizedBox(height: 8),
                Text(headline(item),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: text.displaySmall),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(meta.join(' · '), style: text.labelMedium?.copyWith(color: muted)),
                ],
                if (progress != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(borderRadius: BorderRadius.circular(2), child: Seam(progress)),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  if (item.playable) ...[
                    Expanded(
                      child: FilledButton.icon(
                        style: playButtonStyle(context),
                        onPressed: () => play(context, item),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(item.resumePosition > Duration.zero ? 'Resume' : 'Play'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: info),
                ]),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}

class _StreamLink extends StatelessWidget {
  const _StreamLink();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: OutlinedButton.icon(
          onPressed: () => openMagnet(context),
          icon: const Icon(Icons.add_link),
          label: const Text('Stream a link'),
        ),
      );
}

class _UpNextCard extends StatelessWidget {
  const _UpNextCard(this.item);
  final Item item;

  @override
  Widget build(BuildContext context) {
    final c = session.client!;
    final progress = progressOf(item);
    final text = Theme.of(context).textTheme;
    // Episode primaries are 16:9 stills; movies need their backdrop.
    final url = item.type == 'Episode' ? c.imageUrl(item.id, maxHeight: 300) : c.backdropUrl(item.id, maxWidth: 600);
    return SizedBox(
      width: 248,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => openItem(context, item),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 140,
              child: Stack(fit: StackFit.expand, children: [
                NetImage(url, fallback: c.imageUrl(item.id)),
                if (progress != null) Align(alignment: Alignment.bottomCenter, child: Seam(progress)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(headline(item), maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
          Text(episodeLine(item) ?? timeLeft(item) ?? 'Continue watching',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          const Skeleton(height: 440, radius: 0),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Skeleton(width: 120, height: 20, radius: 4),
              const SizedBox(height: 12),
              Row(children: const [
                Expanded(child: Skeleton(height: 140)),
                SizedBox(width: 12),
                Expanded(child: Skeleton(height: 140)),
              ]),
            ]),
          ),
        ],
      );
}
