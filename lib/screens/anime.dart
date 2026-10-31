import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../anime.dart';
import '../miruro_browser.dart';
import '../playback.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'discover.dart';

String _message(Object error) => error is AnimeException
    ? error.toString()
    : 'Could not load anime. Try again.';

class AnimeTab extends StatefulWidget {
  const AnimeTab({this.client, super.key});
  final Anime? client;
  @override
  State<AnimeTab> createState() => _AnimeTabState();
}

class _AnimeTabState extends State<AnimeTab> {
  final _browser = MiruroBrowser();
  late final _anime = widget.client ?? Anime(browser: _browser.request);
  final _search = TextEditingController();
  List<AnimeCard> _results = [];
  (String, String, String)? _selected;
  String? _error;
  bool _busy = false, _searched = false;
  int _generation = 0;

  Future<void> _find(String query) async {
    final token = ++_generation;
    setState(() {
      _busy = query.trim().isNotEmpty;
      _searched = _busy;
      _error = null;
      _results = [];
    });
    if (!_busy) return;
    try {
      final results = await _anime.search(query);
      if (mounted && token == _generation) setState(() => _results = results);
    } catch (e) {
      if (mounted && token == _generation) setState(() => _error = _message(e));
    } finally {
      if (mounted && token == _generation) setState(() => _busy = false);
    }
  }

  void _cancelBrowser() =>
      unawaited(_browser.cancel().catchError((Object _) {}));

  @override
  void dispose() {
    _cancelBrowser();
    _anime.close();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: FlickTokens.background,
    child: ListenableBuilder(
      listenable: addons,
      builder: (context, _) {
        final catalogs = addons.animeCatalogs;
        final selected = catalogs.where(
          (c) => (c.addon.base, c.type, c.id) == _selected,
        ).firstOrNull ?? catalogs.firstOrNull;
        final heroes = !MediaQuery.disableAnimationsOf(context);
        return SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        style: FlickText.body,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _find,
                        onChanged: (q) {
                          if (q.trim().isEmpty) _find(q);
                        },
                        decoration: InputDecoration(
                          labelText: 'Search anime',
                          constraints: const BoxConstraints(minHeight: 56),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            tooltip: 'Search anime',
                            constraints: const BoxConstraints(
                              minWidth: FlickTokens.minTouchTarget,
                              minHeight: FlickTokens.minTouchTarget,
                            ),
                            onPressed: () => _find(_search.text),
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ),
                      ),
                    ),
                    if (session.showProfile) ...[const SizedBox(width: 12), const ProfileButton()],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: IndexedStack(
                  index: _searched ? 1 : 0,
                  children: [
                    HeroMode(
                      enabled: heroes && !_searched,
                      child: Column(
                        children: [
                          if (catalogs.isNotEmpty) ...[
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
                              child: Row(
                                children: [
                                  for (final c in catalogs) ...[
                                    if (c != catalogs.first) const SizedBox(width: 8),
                                    ChoiceChip(
                                      label: Text(c.name),
                                      selected: c == selected,
                                      showCheckmark: false,
                                      materialTapTargetSize: MaterialTapTargetSize.padded,
                                      onSelected: (_) {
                                        if (c == selected) return;
                                        HapticFeedback.selectionClick();
                                        setState(() => _selected = (c.addon.base, c.type, c.id));
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Expanded(
                            child: selected == null
                                ? CatalogNotice(
                                    Icons.video_library_outlined,
                                    'No anime catalogs are switched on.',
                                    action: 'Sources',
                                    onAction: () => Navigator.pushNamed(context, '/sources'),
                                  )
                                : CatalogFeed(
                                    selected,
                                    key: ValueKey((selected.addon.base, selected.type, selected.id)),
                                  ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
                        if (_error != null)
                          TextButton(
                            onPressed: () => _find(_search.text),
                            child: const Text('Retry'),
                          ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: FlickTokens.pageGutter),
                            child: _busy
                                ? const GridSkeleton(padding: EdgeInsets.zero)
                                : !_searched
                                ? const SizedBox.shrink()
                                : _error == null && _results.isEmpty
                                ? const Center(child: Text('No anime found.'))
                                : ListView.builder(
                                    itemCount: _results.length,
                                    itemBuilder: (context, index) {
                                      final card = _results[index];
                                      return ListTile(
                                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                        leading: SizedBox(
                                          width: 48,
                                          height: 72,
                                          child: card.poster == null
                                              ? const Icon(Icons.movie_outlined)
                                              : NetImage(card.poster!),
                                        ),
                                        title: Text(card.title),
                                        trailing: const Icon(Icons.chevron_right),
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                _AnimeEpisodes(card, _anime, _cancelBrowser),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _AnimeEpisodes extends StatefulWidget {
  const _AnimeEpisodes(this.card, this.anime, this.cancel);
  final AnimeCard card;
  final Anime anime;
  final VoidCallback cancel;
  @override
  State<_AnimeEpisodes> createState() => _AnimeEpisodesState();
}

class _AnimeEpisodesState extends State<_AnimeEpisodes> {
  late Future<List<AnimeEpisode>> _episodes = widget.anime.episodes(
    widget.card.id,
  );
  @override
  void dispose() {
    widget.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.card.title)),
    body: FutureBuilder(
      future: _episodes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(FlickTokens.pageGutter),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_message(snapshot.error!)),
                  TextButton(
                    onPressed: () => setState(
                      () => _episodes = widget.anime.episodes(widget.card.id),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(FlickTokens.pageGutter),
            child: Text('Finding episodes…'),
          );
        }
        final episodes = snapshot.data!;
        if (episodes.isEmpty) {
          return const Center(child: Text('No episodes available.'));
        }
        return ListView.builder(
          itemCount: episodes.length,
          itemBuilder: (context, index) {
            final episode = episodes[index];
            return ListTile(
              leading: Text('${episode.number}', style: FlickText.metadata),
              title: Text(episode.title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnimeSourcesScreen(
                    card: widget.card,
                    episode: episode,
                    anime: widget.anime,
                    cancel: widget.cancel,
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class AnimeSourcesScreen extends StatefulWidget {
  const AnimeSourcesScreen({
    required this.card,
    required this.episode,
    required this.anime,
    required this.cancel,
    super.key,
  });
  final AnimeCard card;
  final AnimeEpisode episode;
  final Anime anime;
  final VoidCallback cancel;
  @override
  State<AnimeSourcesScreen> createState() => _AnimeSourcesScreenState();
}

class _AnimeSourcesScreenState extends State<AnimeSourcesScreen> {
  AnimeResolution? _result;
  String _language = 'sub';
  String? _provider, _error, _notice;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    ++_generation;
    widget.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await widget.anime.resolve(widget.episode);
      if (!mounted || token != _generation) return;
      setState(() {
        _result = result;
        final available = result.variants.where((v) => v.language == _language);
        if (!available.any((v) => v.provider == _provider)) {
          _provider = available.firstOrNull?.provider;
        }
      });
    } catch (e) {
      if (mounted && token == _generation) setState(() => _error = _message(e));
    } finally {
      if (mounted && token == _generation) setState(() => _busy = false);
    }
  }

  void _choose({String? language, String? provider}) {
    ++_generation;
    widget.cancel();
    setState(() {
      _busy = false;
      _error = null;
      _notice = null;
      if (language != null) {
        _language = language;
        _provider = _result?.variants
            .where((v) => v.language == language)
            .firstOrNull
            ?.provider;
      } else {
        _provider = provider;
      }
    });
  }

  Future<void> _act(
    AnimeVariant variant,
    AnimeLink link, {
    String? copy,
    bool download = false,
  }) async {
    final token = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final result = await widget.anime.resolve(widget.episode);
      if (!mounted || token != _generation) return;
      final fresh = result.variants
          .where(
            (v) =>
                v.provider == variant.provider &&
                v.language == variant.language,
          )
          .firstOrNull;
      final target = (download ? fresh?.downloads : fresh?.streams)
          ?.where(
            (s) =>
                s.server == link.server &&
                s.quality == link.quality &&
                s.kind == link.kind,
          )
          .singleOrNull;
      if (fresh == null || target == null) {
        throw const AnimeException(AnimeError.unavailable);
      }
      setState(() => _result = result);
      if (copy != null) {
        await Clipboard.setData(
          ClipboardData(
            text: copy == 'headers'
                ? jsonEncode({'url': target.url, 'headers': target.headers})
                : target.url,
          ),
        );
        if (mounted && token == _generation) {
          setState(() => _notice = 'Copied. Links may expire.');
        }
      } else {
        await play(context, animeStream(fresh, target), (
          title: widget.card.title,
          subtitle: widget.episode.title,
          logo: null,
          poster: widget.card.poster,
          type: 'anime',
          videoId: 'anilist:${widget.card.id}:${widget.episode.number}',
          season: null,
          episode: widget.episode.number,
          meta: null,
        ));
      }
    } catch (e) {
      if (mounted && token == _generation) setState(() => _error = _message(e));
    } finally {
      if (mounted && token == _generation) setState(() => _busy = false);
    }
  }

  Widget _links(
    AnimeVariant variant,
    List<AnimeLink> links, {
    bool download = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final link in links)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${switch (link.kind) {
                    AnimeLinkKind.hls => 'HLS playlist',
                    AnimeLinkKind.file => 'Direct file',
                    AnimeLinkKind.page => 'Download page',
                  }} · ${link.quality ?? 'Quality unknown'}',
                ),
                if (link.server.isNotEmpty)
                  Text(link.server, style: FlickText.metadata),
                Wrap(
                  spacing: 8,
                  children: [
                    if (!download && link.kind != AnimeLinkKind.page)
                      TextButton(
                        onPressed: _busy ? null : () => _act(variant, link),
                        child: const Text('Play'),
                      ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              variant,
                              link,
                              copy: 'url',
                              download: download,
                            ),
                      child: const Text('Copy URL'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _act(
                              variant,
                              link,
                              copy: 'headers',
                              download: download,
                            ),
                      child: const Text('Copy URL + headers'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final variants =
        _result?.variants.where((v) => v.language == _language).toList() ??
        <AnimeVariant>[];
    final selected = variants.where((v) => v.provider == _provider).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text('Episode ${widget.episode.number} sources')),
      body: ListView(
        padding: const EdgeInsets.all(FlickTokens.pageGutter),
        children: [
          Text(widget.card.title, style: FlickText.railHeading),
          Text(widget.episode.title),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in [
                ('sub', 'Sub'),
                ('ssub', 'Soft sub'),
                ('dub', 'Dub'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _language == value,
                  onSelected: (_) => _choose(language: value),
                ),
            ],
          ),
          if (_result != null)
            Wrap(
              spacing: 8,
              children: [
                for (final v in variants)
                  ChoiceChip(
                    label: Text(v.provider),
                    selected: v.provider == _provider,
                    onSelected: (_) => _choose(provider: v.provider),
                  ),
              ],
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Finding fresh links…'),
            ),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          if (!_busy)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _load,
                child: const Text('Refresh sources'),
              ),
            ),
          if (_result != null && variants.isEmpty)
            const Text('No sources for this language.'),
          if (selected != null) ...[
            if (selected.streams.isEmpty)
              const Text('No playable media URLs for this provider.'),
            _links(selected, selected.streams),
            const SizedBox(height: 16),
            const Text('Download links', style: FlickText.railHeading),
            if (selected.downloads.isEmpty)
              const Text('No provider download URL returned.'),
            _links(selected, selected.downloads, download: true),
          ],
        ],
      ),
    );
  }
}
