import 'addons.dart';

/// The episode the Up Next card names; [label] reads like "S1 E3".
typedef NextEpisode = ({String label, String title, String? thumbnail});

/// What the player offers near the end of an episode. It calls [resolve] once, caches the answer, and pops its
/// route with it; the caller's play loop decides what that answer means.
typedef NextUp = ({
  NextEpisode episode,
  Duration? outro, // Jellyfin Outro start; null = unknown
  Future<Object?> Function() resolve,
});

/// "S1 E3": the one episode label for the Streams screen and Up Next.
String episodeLabel(int? season, int? episode) => 'S${season ?? 0} E${episode ?? 0}';

/// The video after [id] in season/episode order (stremio-core next_video): null when [id] is unknown or last, and
/// never a step from a regular season into specials (season 0).
Video? nextVideo(List<Video> videos, String id) {
  final sorted = [...videos]..sort((a, b) {
      final s = (a.season ?? 0).compareTo(b.season ?? 0);
      return s != 0 ? s : (a.episode ?? 0).compareTo(b.episode ?? 0);
    });
  final i = sorted.indexWhere((v) => v.id == id);
  if (i < 0 || i + 1 >= sorted.length) return null;
  final next = sorted[i + 1];
  return (sorted[i].season ?? 0) >= 1 && (next.season ?? 0) == 0 ? null : next;
}

/// The stream in the same `behaviorHints.bingeGroup`, so the next episode keeps the release and quality.
AddonStream? bingeMatch(List<AddonStream> streams, String? group) =>
    group == null ? null : streams.where((s) => s.bingeGroup == group).firstOrNull;

/// When Up Next shows: the Jellyfin outro if it is plausible (second half, at least 5 s before the end), else 30 s
/// before the end. Null for clips under 3 minutes.
Duration? upNextAt(Duration duration, {Duration? outro}) {
  if (duration < const Duration(minutes: 3)) return null;
  if (outro != null && outro * 2 >= duration && outro <= duration - const Duration(seconds: 5)) return outro;
  return duration - const Duration(seconds: 30);
}

const countdownLength = Duration(seconds: 10);

/// What the Up Next card shows. [countdown] is the autoplay progress 0..1, null when there is no countdown.
typedef UpNextView = ({bool visible, double? countdown, int secondsLeft, bool resolving});

UpNextView upNextView({required Duration position, required Duration duration, Duration? outro,
    required bool dismissed, required bool forced, required bool autoplay, required Duration counted,
    required bool resolving}) {
  final at = upNextAt(duration, outro: outro);
  final visible = forced || (!dismissed && at != null && position >= at);
  final left = countdownLength - counted;
  return (
    visible: visible,
    countdown: !autoplay || forced || !visible
        ? null
        : (counted.inMicroseconds / countdownLength.inMicroseconds).clamp(0.0, 1.0),
    secondsLeft: (left.inMicroseconds / Duration.microsecondsPerSecond).ceil().clamp(0, countdownLength.inSeconds),
    resolving: resolving,
  );
}
