import 'package:flutter/material.dart';

import 'addons.dart';
import 'screens/player.dart';
import 'screens/torrent.dart';

/// What the player needs to name a title and find its subtitles.
typedef Playback = ({String title, String? subtitle, String type, String videoId, int? season, int? episode});

/// Plays [s]: url → player, infoHash → torrent start (fileIdx, else a guessed file),
/// externalUrl → the service's app or site. Returns when the user is back on the stream list.
Future<void> play(BuildContext context, AddonStream s, Playback p) async {
  final external = s.externalUrl, url = s.url;
  if (external != null) {
    await openExternal(external);
    return;
  }
  final title = _name(p);
  final Widget screen;
  if (url != null) {
    screen = PlayerScreen(
        title: title, source: url, headers: s.headers, subtitles: s.subtitles,
        playback: p, filename: s.filename, size: s.videoSize, hash: s.videoHash);
  } else if (s.infoHash != null) {
    screen = TorrentScreen(magnetFor(s), fileIdx: s.fileIdx,
        season: p.season, episode: p.episode, title: title,
        playback: p, subtitles: s.subtitles, hash: s.videoHash);
  } else {
    throw ArgumentError('Stream has no playable source');
  }
  await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

String _name(Playback p) => p.subtitle == null ? p.title : '${p.title} · ${p.subtitle}';

/// Downloads torrent stream [s]: the torrent start screen picks the file like [play], registers it and comes back.
Future<void> download(BuildContext context, AddonStream s, Playback p, {String? poster}) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => TorrentScreen(magnetFor(s), fileIdx: s.fileIdx,
        season: p.season, episode: p.episode, title: _name(p), playback: p, download: true, poster: poster)));
