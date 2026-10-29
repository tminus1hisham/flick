import 'package:flutter/material.dart';

import 'addons.dart';
import 'jellyfin.dart';
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
  final title = p.subtitle == null ? p.title : '${p.title} · ${p.subtitle}';
  final Widget screen;
  if (url != null) {
    screen = PlayerScreen(
        item: Item({'Id': p.videoId, 'Name': title, 'Type': 'Video'}),
        source: url, report: false, headers: s.headers, subtitles: s.subtitles,
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
