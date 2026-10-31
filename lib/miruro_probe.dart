// Debug entry point: flutter run -t lib/miruro_probe.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';

import 'anime.dart';
import 'miruro_browser.dart';
import 'playback.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await settings.load();
  await addons.load();
  runApp(MaterialApp(theme: flickTheme(), home: const MiruroProbe()));
}

class MiruroProbe extends StatefulWidget {
  const MiruroProbe({super.key});
  @override
  State<MiruroProbe> createState() => _MiruroProbeState();
}

class _MiruroProbeState extends State<MiruroProbe> {
  final _browser = MiruroBrowser();
  late Anime _anime;
  final _id = TextEditingController(text: '20');
  String _origin = miruroOrigins.first;
  final _lines = <String>[];
  bool _busy = false;
  List<AnimeEpisode> _episodes = [];
  AnimeResolution? _result;

  @override
  void initState() {
    super.initState();
    _resetClient();
  }

  void _resetClient() {
    _anime = Anime(
      origin: _origin,
      browser: (uri) async {
        _note('Direct request blocked; opening visible browser.');
        return _browser.request(uri);
      },
    );
  }

  void _note(String line) {
    if (mounted) setState(() => _lines.add(line));
    // Only fixed stage labels: never log bodies, cookies, headers or media URLs.
    debugPrint('miruro-probe: $line');
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } on AnimeException catch (e) {
      _note(e.toString());
    } catch (_) {
      _note('Probe failed. No response details were logged.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _episodesForId() => _run(() async {
    final id = int.tryParse(_id.text);
    if (id == null || id <= 0) {
      _note('Enter a positive AniList ID.');
      return;
    }
    setState(() {
      _episodes = [];
      _result = null;
      _lines.clear();
    });
    _note('Requesting episodes.');
    final episodes = await _anime.episodes(id);
    if (!mounted) return;
    setState(() => _episodes = episodes);
    _note('Episodes decoded: ${episodes.length}.');
  });

  Future<void> _resolve(AnimeEpisode e) => _run(() async {
    setState(() => _result = null);
    _note('Resolving selected episode.');
    final result = await _anime.resolve(e);
    if (!mounted) return;
    setState(() => _result = result);
    _note(
      'Source decoded: ${result.variants.length} provider/track combinations.',
    );
  });

  Future<void> _testMedia(AnimeLink link) => _run(() async {
    final client = http.Client();
    var stage = 'Playlist';
    try {
      var uri = Uri.parse(link.url);
      for (var depth = 0; depth < 4; depth++) {
        final request = http.Request('GET', uri)
          ..headers.addAll(link.headers)
          ..followRedirects = false;
        if (stage == 'Segment' || link.kind == AnimeLinkKind.file) {
          request.headers['Range'] = 'bytes=0-1023';
        }
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 && response.statusCode != 206) {
          _note('$stage failed: HTTP ${response.statusCode}.');
          return;
        }
        if (stage == 'Segment' || link.kind == AnimeLinkKind.file) {
          final first = await response.stream.first.timeout(
            const Duration(seconds: 20),
          );
          _note(
            first.isEmpty
                ? '$stage returned no bytes.'
                : '$stage bytes received.',
          );
          return;
        }
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 20),
        )) {
          if (bytes.length + chunk.length > 1024 * 1024) {
            _note('Playlist exceeded probe limit.');
            return;
          }
          bytes.addAll(chunk);
        }
        final text = utf8.decode(bytes);
        if (!text.trimLeft().startsWith('#EXTM3U')) {
          _note('Playlist is not HLS.');
          return;
        }
        _note('Playlist decoded.');
        final child = const LineSplitter()
            .convert(text)
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty && !s.startsWith('#'))
            .firstOrNull;
        if (child == null) {
          _note('Playlist has no media references.');
          return;
        }
        uri = uri.resolve(child);
        if (!['http', 'https'].contains(uri.scheme) ||
            uri.userInfo.isNotEmpty) {
          _note('Playlist has an unsupported media reference.');
          return;
        }
        if (!text.contains('#EXT-X-STREAM-INF')) stage = 'Segment';
      }
      _note('Playlist nesting exceeded probe limit.');
    } catch (_) {
      _note('$stage request failed.');
    } finally {
      client.close();
    }
  });

  Future<void> _copy(AnimeLink link, bool withHeaders) async {
    await Clipboard.setData(
      ClipboardData(
        text: withHeaders
            ? jsonEncode({'url': link.url, 'headers': link.headers})
            : link.url,
      ),
    );
    _note('Copied.');
  }

  @override
  void dispose() {
    _anime.close();
    _browser.cancel();
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Miruro access probe')),
    body: ListView(
      padding: const EdgeInsets.all(FlickTokens.pageGutter),
      children: [
        const Text(
          'Device validation only. A resolved URL is not proof that its media can play.',
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _origin,
          isExpanded: true,
          items: [
            for (final o in miruroOrigins)
              DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: _busy
              ? null
              : (v) {
                  if (v != null) {
                    _anime.close();
                    setState(() {
                      _origin = v;
                      _episodes = [];
                      _result = null;
                    });
                    _resetClient();
                  }
                },
        ),
        TextField(
          controller: _id,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'AniList ID'),
        ),
        FilledButton(
          onPressed: _busy ? null : _episodesForId,
          child: const Text('Fetch episode list'),
        ),
        for (final line in _lines) Text(line),
        if (_busy) const Text('Waiting for the source…'),
        for (final e in _episodes.where((e) => e.number == 1))
          OutlinedButton(
            onPressed: _busy ? null : () => _resolve(e),
            child: Text('Resolve Episode ${e.number}'),
          ),
        if (_result case final AnimeResolution result) ...[
          for (final variant in result.variants) ...[
            Text('${variant.provider} · ${variant.language}'),
            if (variant.downloads.isEmpty)
              const Text('No provider download URL returned.'),
            for (final link in [...variant.streams, ...variant.downloads]) ...[
              Text('${link.kind.name} · ${link.quality ?? 'Unknown quality'}'),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _copy(link, false),
                    child: const Text('Copy URL'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _copy(link, true),
                    child: const Text('Copy URL + headers'),
                  ),
                  if (link.kind != AnimeLinkKind.page) ...[
                    TextButton(
                      onPressed: _busy ? null : () => _testMedia(link),
                      child: const Text('Test media access'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => play(context, animeStream(variant, link), (
                              title: 'Anime ${result.episode.animeId}',
                              subtitle: result.episode.title,
                              type: 'anime',
                              videoId:
                                  'anilist:${result.episode.animeId}:${result.episode.number}',
                              season: null,
                              episode: result.episode.number,
                              meta: null,
                            )),
                      child: const Text('Play'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ],
      ],
    ),
  );
}
