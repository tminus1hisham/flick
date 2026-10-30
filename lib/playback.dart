import 'package:flutter/material.dart';

import 'addons.dart';
import 'jellyfin.dart';
import 'screens/player.dart';
import 'screens/title.dart';
import 'screens/torrent.dart';
import 'state.dart';
import 'upnext.dart';

/// What the player needs to name a title and find its subtitles; [meta] (series only) finds the next episode.
typedef Playback = ({
  String title,
  String? subtitle,
  String type,
  String videoId,
  int? season,
  int? episode,
  Meta? meta,
});

/// One episode's [Playback]; the Streams screen and Up Next both build it here so they stay identical.
Playback episodePlayback(Meta meta, Video video) {
  final ep = episodeLabel(video.season, video.episode);
  return (
    title: meta.name,
    subtitle: video.title.isEmpty ? ep : '$ep · ${video.title}',
    type: meta.type,
    videoId: video.id,
    season: video.season,
    episode: video.episode,
    meta: meta,
  );
}

/// What an addon episode's player pops with when the user moves on to the next episode.
sealed class AddonNext {}

/// The next episode's stream in the same binge group: plays straight away.
final class NextStream extends AddonNext {
  NextStream(this.stream, this.playback, this.addon);
  final AddonStream stream;
  final Playback playback;
  final Addon addon;
}

/// No stream to continue with: the user picks one on the next episode's Streams screen.
final class PickStream extends AddonNext {
  PickStream(this.meta, this.video);
  final Meta meta;
  final Video video;
}

/// Plays [s]: url → player, infoHash → torrent start (fileIdx, else a guessed file),
/// externalUrl → the service's app or site. [addon] (the source of [s]) lets Up Next find the next episode's
/// stream in the same binge group. Returns when the user is back on a stream list.
Future<void> play(BuildContext context, AddonStream s, Playback p, {Addon? addon}) async {
  while (true) {
    final external = s.externalUrl, url = s.url;
    if (external != null) {
      await openExternal(external);
      return;
    }
    final title = p.subtitle == null ? p.title : '${p.title} · ${p.subtitle}';
    final next = _nextUp(s, p, addon);
    final Widget screen;
    if (url != null) {
      screen = PlayerScreen(
          item: Item({'Id': p.videoId, 'Name': title, 'Type': 'Video'}),
          source: url, report: false, headers: s.headers, subtitles: s.subtitles,
          playback: p, filename: s.filename, size: s.videoSize, hash: s.videoHash, next: next);
    } else if (s.infoHash != null) {
      screen = TorrentScreen(magnetFor(s), fileIdx: s.fileIdx,
          season: p.season, episode: p.episode, title: title,
          playback: p, subtitles: s.subtitles, hash: s.videoHash, next: next);
    } else {
      throw ArgumentError('Stream has no playable source');
    }
    final result = await Navigator.push<Object?>(context, MaterialPageRoute(builder: (_) => screen));
    if (!context.mounted) return;
    switch (result) {
      case NextStream r:
        (s, p, addon) = (r.stream, r.playback, r.addon);
      case PickStream r:
        Navigator.push(context, MaterialPageRoute(builder: (_) => StreamsScreen(r.meta, r.video)));
        return;
      default:
        return;
    }
  }
}

/// Up Next for an addon episode: null for movies and the last episode. Resolving never throws; anything short
/// of a binge-group match sends the user to pick a stream.
Future<NextUp?>? _nextUp(AddonStream s, Playback p, Addon? addon) {
  final meta = p.meta, group = s.bingeGroup;
  final video = meta == null ? null : nextVideo(meta.videos, p.videoId);
  if (meta == null || video == null) return null;
  final NextUp up = (
    episode: (label: episodeLabel(video.season, video.episode), title: video.title, thumbnail: video.thumbnail),
    outro: null,
    resolve: () async {
      if (addon != null && group != null) {
        try {
          final match = bingeMatch(await addons.streams(addon, meta.type, video.id), group);
          if (match != null) return NextStream(match, episodePlayback(meta, video), addon);
        } catch (_) {}
      }
      return PickStream(meta, video);
    },
  );
  return Future.value(up);
}
