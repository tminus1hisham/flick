import 'dart:async';

import 'package:flutter/material.dart';

import '../anime.dart';
import '../history.dart';
import '../kit/focus.dart';
import '../miruro_browser.dart';
import '../player_keys.dart' show playerTime;
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'anime.dart';
import 'title.dart';

/// Checkpoints contain content identity only; opening one always finds fresh sources.
class ContinueWatching extends StatelessWidget {
  const ContinueWatching({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: history, builder: (context, _) {
    final entries = history.entries;
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(vertical: FlickTokens.railGap),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.symmetric(horizontal: context.tv ? FlickTv.gridPad : FlickTokens.pageGutter),
          child: Text('Continue Watching', style: context.tv ? FlickTv.railHeading : FlickText.railHeading)),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.tv ? FlickTv.gridPad : FlickTokens.pageGutter,
            vertical: FlickTokens.railGap),
          child: Row(children: [for (final progress in entries) Padding(
            key: ValueKey(progress.key), padding: const EdgeInsets.only(right: FlickTokens.railGap),
            child: Builder(builder: (context) {
              void open() => Navigator.push(context, MaterialPageRoute(builder: (_) => WatchSourcesScreen(progress)));
              final label = '${progress.title}, ${progress.subtitle ?? ''}, resume at ${playerTime(progress.position)}';
              final content = Container(
                width: context.tv ? 280 : 220,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: FlickTokens.surface1,
                  borderRadius: BorderRadius.circular(FlickTokens.controlRadius)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(progress.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: context.tv ? FlickTv.body : FlickText.body),
                  if (progress.subtitle != null) Text(progress.subtitle!, maxLines: 1,
                    overflow: TextOverflow.ellipsis, style: context.tv ? FlickTv.meta : FlickText.metadata),
                  Text('Resume · ${playerTime(progress.position)}', style: context.tv ? FlickTv.meta : FlickText.metadata),
                ]),
              );
              if (context.tv) { return RevealArea(child: FocusFrame.button(
                semanticLabel: label, onActivate: open, child: content)); }
              return Semantics(label: label, button: true, onTap: open, excludeSemantics: true,
                child: InkWell(onTap: open, borderRadius: BorderRadius.circular(FlickTokens.controlRadius), child: content));
            }),
          )]),
        ),
      ]),
    );
  });
}

/// Resolves the exact saved episode, never a nearby episode or a saved media URL.
class WatchSourcesScreen extends StatefulWidget {
  const WatchSourcesScreen(this.progress, {this.anime, super.key});
  final WatchProgress progress;
  final Anime? anime;

  @override
  State<WatchSourcesScreen> createState() => _WatchSourcesScreenState();
}

class _WatchSourcesScreenState extends State<WatchSourcesScreen> {
  final _browser = MiruroBrowser();
  Anime? _anime;
  late Future<Widget> _screen = _load();

  void _cancel() => unawaited(_browser.cancel().catchError((Object _) {}));

  Future<Widget> _load() async {
    final p = widget.progress;
    final parts = p.videoId.split(':');
    if (p.scope == null && parts.first == 'anilist') {
      final anime = _anime ??= widget.anime ?? Anime(browser: _browser.request);
      final id = int.parse(parts[1]), number = int.parse(parts[2]);
      final episode = (await anime.episodes(id)).where((e) => e.number == number).firstOrNull;
      if (episode == null) throw const AnimeException(AnimeError.unavailable);
      return AnimeSourcesScreen(card: (id: id, title: p.title, poster: p.poster),
        episode: episode, anime: anime, cancel: _cancel);
    }
    final id = p.scope?.titleId ?? (parts.first == 'kitsu' ? parts.take(2).join(':') : parts.first);
    if (p.type == 'movie') return TitleScreen((id: id, type: p.type, name: p.title, poster: p.poster, scope: p.scope, releaseInfo: null));
    final meta = await addons.scopedMeta(p.type, id, p.scope);
    final video = meta.videos.where((v) => v.id == p.videoId).firstOrNull;
    if (video == null) throw StateError('This episode is no longer listed by your sources.');
    return StreamsScreen(meta, video);
  }

  @override
  void dispose() {
    if (_anime != null) {
      _cancel();
      if (widget.anime == null) _anime!.close();
    }
    super.dispose();
  }

  Widget _action(String label, VoidCallback action) => context.tv
    ? FocusFrame.button(semanticLabel: label, onActivate: action,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(label, style: FlickTv.body)))
    : TextButton(onPressed: action, child: Text(label));

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(future: _screen, builder: (context, snapshot) {
    if (snapshot.hasData) return snapshot.data!;
    return Scaffold(body: SafeArea(child: FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
      child: ListView(padding: EdgeInsets.all(context.tv ? FlickTv.insetH : FlickTokens.pageGutter), children: [
        Align(alignment: Alignment.centerLeft, child: _action('Back', () => Navigator.pop(context))),
        Text(widget.progress.title, style: context.tv ? FlickTv.page : FlickText.pageTitle),
        const SizedBox(height: FlickTokens.railGap),
        if (snapshot.hasError) ...[
          Text('Could not find this video. Check your connection and enabled sources, then retry.',
            style: context.tv ? FlickTv.body : FlickText.body),
          Align(alignment: Alignment.centerLeft, child: _action('Retry', () => setState(() {
            _screen = _load();
            // An immediate failure can arrive before FutureBuilder subscribes on the next frame.
            _screen.ignore();
          }))),
        ] else ...[
          Text('Finding sources…', style: context.tv ? FlickTv.body : FlickText.body),
          const SizedBox(height: FlickTokens.railGap),
          const Skeleton(height: 72),
        ],
      ]),
    )));
  });
}
