import 'package:flutter/material.dart';

import 'addons.dart';
import 'history.dart';
import 'kit/route.dart';
import 'live.dart';
import 'queue.dart';
import 'screens/movie_queue.dart';
import 'screens/player.dart';
import 'screens/title.dart';
import 'screens/torrent.dart';
import 'state.dart';
import 'upnext.dart';

/// What the player needs to name a title and find its subtitles; [meta] (series only) finds the next episode.
typedef Playback = ({
  ContentScope? scope,
  String title,
  String? subtitle,
  String? logo,
  String? poster,
  String type,
  String videoId,
  int? season,
  int? episode,
  Meta? meta,
});

Future<void> playLive(BuildContext context, String title, LiveSource source, Future<LiveSource> Function() resolve,
    {LiveEvent? event, LiveChannel? channel, LiveClient? client}) =>
    Navigator.push<void>(context, EpisodeRoute(builder: (_) => PlayerScreen(
      title: title, source: source.url, headers: source.headers, live: true, resolveLive: resolve,
      liveEvent: event, liveChannel: channel, liveClient: client,
    )));

Playback moviePlayback(QueuedMovie item) => (title: item.title, subtitle: null, logo: null,
  poster: item.poster, type: 'movie', videoId: item.id, season: null, episode: null, scope: item.scope, meta: null);

class MovieNext {
  MovieNext(this.choice);
  final MovieChoice choice;
}

/// Direct offline player routes use the same queue handoff as addon playback.
Future<void> continueMovieQueue(BuildContext context, Object? result) async {
  if (result is! MovieNext || !context.mounted) return;
  final choice = result.choice;
  await play(context, choice.stream, moviePlayback(choice.item), addon: choice.addon,
    start: choice.item.start, queued: choice.item);
}

/// One episode's [Playback]; the Streams screen and Up Next both build it here so they stay identical.
Playback episodePlayback(Meta meta, Video video) {
  final ep = episodeLabel(video.season, video.episode);
  return (
    title: meta.name,
    subtitle: video.title.isEmpty ? ep : '$ep · ${video.title}',
    logo: meta.logo,
    poster: meta.poster,
    type: meta.type,
    videoId: video.id,
    season: video.season,
    episode: video.episode,
    meta: meta,
    scope: videoScope(video.id, meta.scope),
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
Future<void> play(BuildContext context, AddonStream s, Playback p, {Addon? addon, Duration? start, QueuedMovie? queued}) async {
  queued ??= movieQueue.items.where((m) => m.sameMovie(p.videoId, addon?.base) && p.type == 'movie').firstOrNull;
  for (var moved = false;; moved = true) {
    final external = s.externalUrl, url = s.url;
    if (external != null) {
      await openExternal(external);
      return;
    }
    final title = p.subtitle == null ? p.title : '${p.title} · ${p.subtitle}';
    final next = _nextUp(s, p, addon);
    final pending = queued;
    void started() {
      if (pending != null) movieQueue.remove(pending);
    }
    final Widget screen;
    if (url != null) {
      screen = PlayerScreen(
          title: title, source: url, headers: s.headers, subtitles: s.subtitles,
          playback: p, start: start, onStarted: started, filename: s.filename, size: s.videoSize, hash: s.videoHash, next: next);
    } else if (s.infoHash != null) {
      screen = TorrentScreen(magnetFor(s), fileIdx: s.fileIdx,
          season: p.season, episode: p.episode, title: title,
          playback: p, start: start, onStarted: started, subtitles: s.subtitles, hash: s.videoHash, next: next);
    } else {
      throw ArgumentError('Stream has no playable source');
    }
    final result = await Navigator.push<Object?>(context, EpisodeRoute(builder: (_) => screen, next: moved));
    if (!context.mounted) return;
    switch (result) {
      case MovieNext r:
        final choice = r.choice;
        (s, p, addon, queued, start) = (choice.stream, moviePlayback(choice.item), choice.addon, choice.item, choice.item.start);
      case NextStream r:
        (s, p, addon) = (r.stream, r.playback, r.addon);
        start = null;
        queued = null;
      case PickStream r:
        Navigator.push(context, EpisodeRoute(builder: (_) => StreamsScreen(r.meta, r.video), next: true));
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
    resolve: () => resolveNext(addon, meta, video, group),
  );
  return Future.value(up);
}

/// The stremio-core rule: the same addon's stream in the same binge group plays on; no addon, no group, no match
/// or a failed fetch means the user picks a stream. Never throws.
Future<AddonNext> resolveNext(Addon? addon, Meta meta, Video video, String? group) async {
  if (addon != null && group != null) {
    try {
      final match = bingeMatch(await addons.streams(addon, meta.type, video.id), group);
      if (match != null) return NextStream(match, episodePlayback(meta, video), addon);
    } catch (_) {}
  }
  return PickStream(meta, video);
}
