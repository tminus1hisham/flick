import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../kit/route.dart';
import '../addons.dart' show Subtitle;
import '../playback.dart';
import '../stall.dart';
import '../state.dart';
import '../theme.dart';
import '../torrent.dart';
import '../upnext.dart';
import '../widgets.dart';
import 'buffering.dart';
import 'upnext.dart';

typedef _Caption = ({
  SubtitleTrack track,

  /// Addon or stream subtitle file; null for embedded tracks and Off.
  String? url,
  String lang,
  String label,
  String detail,
});

const _subtitleLanguages = <String, (String, String)>{
  'eng': ('en', 'English'),
  'spa': ('es', 'Spanish'),
  'fre': ('fr', 'French'),
  'fra': ('fr', 'French'),
  'ger': ('de', 'German'),
  'deu': ('de', 'German'),
  'por': ('pt', 'Portuguese'),
  'ita': ('it', 'Italian'),
  'dut': ('nl', 'Dutch'),
  'nld': ('nl', 'Dutch'),
  'pol': ('pl', 'Polish'),
  'rus': ('ru', 'Russian'),
  'tur': ('tr', 'Turkish'),
  'ara': ('ar', 'Arabic'),
  'swa': ('sw', 'Swahili'),
  'jpn': ('ja', 'Japanese'),
  'chi': ('zh', 'Chinese'),
  'zho': ('zh', 'Chinese'),
  'kor': ('ko', 'Korean'),
  'hin': ('hi', 'Hindi'),
  'ukr': ('uk', 'Ukrainian'),
  'swe': ('sv', 'Swedish'),
  'dan': ('da', 'Danish'),
  'nor': ('no', 'Norwegian'),
  'fin': ('fi', 'Finnish'),
  'ces': ('cs', 'Czech'),
  'cze': ('cs', 'Czech'),
  'ell': ('el', 'Greek'),
  'gre': ('el', 'Greek'),
  'ron': ('ro', 'Romanian'),
  'rum': ('ro', 'Romanian'),
  'hun': ('hu', 'Hungarian'),
  'ind': ('id', 'Indonesian'),
  'vie': ('vi', 'Vietnamese'),
  'tha': ('th', 'Thai'),
  'heb': ('he', 'Hebrew'),
  'und': ('und', 'Unknown language'),
};

/// Stremio uses ISO 639-2; platform locales and some embedded tracks use 639-1.
String subtitleLanguage(String code) {
  final base = code.toLowerCase().split(RegExp('[-_]')).first;
  return _subtitleLanguages[base]?.$1 ?? base;
}

String subtitleLanguageName(String code) {
  final normalized = subtitleLanguage(code);
  for (final entry in _subtitleLanguages.values) {
    if (entry.$1 == normalized) return entry.$2;
  }
  return code.isEmpty ? 'Unknown language' : code;
}

/// Embedded subtitle tracks: mpv lists files added by sub-add as numbered tracks
/// too, so leave out the ids in [added].
List<SubtitleTrack> embeddedSubtitles(
  List<SubtitleTrack> tracks,
  Iterable<String> added,
) => [
  for (final t in tracks)
    if (t.id != 'auto' &&
        t.id != 'no' &&
        !t.uri &&
        !t.data &&
        !added.contains(t.id))
      t,
];

/// The id of the subtitle track sub-add just added and selected, or null if it
/// didn't load: mpv then leaves [sid] on the previous track. [trackList] is
/// mpv's `track-list` as JSON; [known] are the ids of files added earlier.
String? addedSubtitle(String trackList, String sid, Iterable<String> known) {
  if (known.contains(sid)) return null;
  final tracks = jsonDecode(trackList);
  return tracks is List &&
          tracks.any(
            (t) =>
                t is Map &&
                t['type'] == 'sub' &&
                '${t['id']}' == sid &&
                t['external'] == true,
          )
      ? sid
      : null;
}

/// Whether playback stopping is a failure rather than the video ending. Past
/// 90% (Stremio's CREDITS_THRESHOLD_COEF) or with an unknown duration it ended:
/// .ts files and some MKVs overstate their duration. Short of that it failed
/// only after a stream error with nothing left buffered.
bool stoppedEarly({
  required bool started,
  required bool error,
  required Duration position,
  required Duration duration,
  required Duration buffer,
}) {
  if (!started) return true;
  if (duration <= Duration.zero || position >= duration * 0.9) return false;
  return error && buffer - position < const Duration(seconds: 1);
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.title,
    required this.source,
    this.headers = const {},
    this.subtitles = const [],
    this.playback,
    this.filename,
    this.size,
    this.hash,
    this.torrent,
    this.next,
    super.key,
  });
  final Playback? playback;
  final String? filename, hash;
  final int? size;

  /// Shown when there is no [playback], e.g. for a pasted magnet link.
  final String title;
  final Map<String, String> headers;
  final List<Subtitle> subtitles;

  /// The torrent behind [source] when it is the engine's loopback stream.
  final ({TorrentEngine engine, int id})? torrent;

  /// The next episode, for Up Next; the route pops with its `resolve()` answer. Null for movies.
  final Future<NextUp?>? next;

  /// An addon stream URL, the local torrent stream server or a downloaded file.
  final String source;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 400 * 1024 * 1024),
  );
  late final _controller = VideoController(_player);
  final _pauseWait = PauseWait();
  final _subs = <StreamSubscription>[];
  bool _started = false;
  String? _error;
  bool _retrying = false;
  // Buffering panel (addon playback). An episode runs from open() to the first
  // frame or the error screen (_opening), or from a stall's start to its end.
  DateTime? _since;
  bool _opening = false;
  // Where the current Starting episode opened: mpv can report it before the first frame.
  Duration _openedAt = Duration.zero;
  double? _lastProgress;
  ({int peers, int rate})? _status;
  DateTime? _statusAt;
  bool _online = true;
  Timer? _ticker, _reveal;
  bool _panel = false, _languages = false, _loading = false, _fetched = false;
  bool _manual = false, _autoPicked = false, _bitrateSent = false;
  String? _catalogueError, _subtitleError, _notice, _language, _pending;
  String _search = '';
  final _languageSearch = TextEditingController();
  List<Subtitle> _catalogue = [];
  final _entryFocus = FocusNode();
  final _headingFocus = FocusNode();
  final _scrolls = <String, ScrollController>{};
  SubtitleTrack? _selected;
  _Caption? _failed;
  String? _applicationError;
  String? _lastPlaybackError;
  // Subtitle file text and the mpv track id it was added as, by URL.
  final _subtitleFiles = <String, String>{};
  final _added = <String, String>{};
  // open() resets state.position to 0 until mpv reports time-pos; Retry and the stop check use this instead.
  Duration _pos = Duration.zero;
  // Up Next (design/upnext.md). _token invalidates a commit in flight on dispose.
  NextUp? _next;
  Future<Object?>? _resolved;
  UpNextView? _shown;
  Timer? _countdown;
  Duration _counted = Duration.zero;
  bool _dismissed = false, _forced = false, _resolving = false;
  bool _committed = false, _completed = false, _endedEarly = false;
  int _token = 0;
  // media_kit 2.0.1 never rebuilds its button bars when the theme changes
  // (its updateShouldNotify is inverted), so the Next button listens itself.
  final _nextBar = ValueNotifier(0);
  final _video = GlobalKey<VideoState>();

  // Up Next pushes the next player before this one is disposed: only the last
  // one out restores the system bars and rotation.
  static int _live = 0;

  @override
  void initState() {
    super.initState();
    _live++;
    _immersive();
    _subs
      ..add(
        _player.stream.position.listen((p) {
          // Before the early return: a seek to the start must reset Up Next.
          _upNext(p);
          if (p <= Duration.zero) return;
          _pos = p;
          _pauseWait.position(p, DateTime.now());
          if (!_started) {
            // Errors before playback started weren't fatal after all.
            _started = true;
            _lastPlaybackError = null;
            if (_error != null && mounted) setState(() => _error = null);
          }
          if (_opening && p != _openedAt) {
            _endEpisode();
            if (_player.state.buffering) _beginEpisode(opening: false);
          }
          _autoPick();
        }),
      )
      ..add(
        _player.stream.tracks.listen((_) {
          if (mounted) setState(() {});
          _autoPick();
        }),
      )
      ..add(
        _player.stream.track.listen((_) {
          if (mounted) setState(() {});
        }),
      )
      ..add(
        _player.stream.completed.listen((done) {
          _completed = done;
          _endedEarly = done && _stoppedEarly;
          if (_endedEarly) _fatalError();
          _upNext();
        }),
      )
      ..add(
        _player.stream.playing.listen((playing) {
          if (!playing && _lastPlaybackError != null) _checkStopped();
        }),
      )
      ..add(
        _player.stream.duration.listen((d) {
          _upNext();
          final t = widget.torrent, size = widget.size;
          if (_bitrateSent || t == null || size == null || d.inSeconds <= 0) {
            return;
          }
          _bitrateSent = true;
          // Best-effort: without it the engine assumes 1 MiB/s.
          t.engine.bitrate(t.id, size ~/ d.inSeconds).catchError((_) {});
        }),
      )
      ..add(_player.stream.buffering.listen(_onBuffering))
      ..add(_player.stream.error.listen(_showError));
    _init().catchError(_showError);
    if (widget.playback != null) _fetchSubtitles();
    widget.next?.then((next) {
      if (!mounted) return;
      setState(() => _next = next);
      _nextBar.value++;
      _upNext();
    }, onError: (Object e) => debugPrint('up next: $e'));
  }

  /// The player is landscape and full-bleed, also after leaving fullscreen.
  static Future<void> _immersive() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  UpNextView _upNextView(NextUp next, Duration position) => upNextView(
    position: position,
    duration: _player.state.duration,
    dismissed: _dismissed,
    forced: _forced,
    autoplay: settings.autoplayNext,
    counted: _counted,
    resolving: _resolving,
  );

  /// Re-evaluates Up Next after anything that can change it: resets on a seek
  /// back, prefetches once the card shows, runs the countdown timer only while
  /// the card could count, and plays the next episode after a genuine end.
  void _upNext([Duration? position]) {
    final next = _next;
    if (next == null || !mounted) return;
    final p = position ?? _player.state.position;
    final at = upNextAt(_player.state.duration);
    // Not at 0: open() (Retry) reports 0 until mpv seeks to
    // its start, and that is no seek back.
    if (at != null && p > Duration.zero && p < at) {
      _counted = Duration.zero;
      _dismissed = false;
    }
    final view = _upNextView(next, p);
    if (view.visible) _prefetch(next);
    if (view.visible && _shown?.visible != true) {
      // media_kit's fullscreen is a route above this one: leave it so the
      // card (and its stop controls) can be seen while it counts.
      if (_video.currentState?.isFullscreen() == true) {
        _video.currentState?.exitFullscreen();
      }
    } else if (!view.visible && _shown?.visible == true) {
      // The card's controls are gone: hand focus back to the player.
      _entryFocus.requestFocus();
    }
    if (view.visible && settings.autoplayNext && !_committed) {
      _countdown ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _countdown?.cancel();
      _countdown = null;
    }
    if (_completed &&
        !_committed &&
        onCompletion(
              stoppedEarly: _endedEarly,
              visible: view.visible,
              autoplay: settings.autoplayNext,
              dismissed: _dismissed,
              panel: _panel,
            ) ==
            CompletionStep.now) {
      _commit();
      return;
    }
    if (view != _shown) setState(() => _shown = view);
  }

  void _tick() {
    final next = _next;
    if (next == null || !mounted) return;
    final eligible = countdownEligible(
      visible: _upNextView(next, _player.state.position).visible,
      autoplay: settings.autoplayNext,
      committed: _committed,
      playing: _player.state.playing,
      buffering: _player.state.buffering,
      panel: _panel,
    );
    if (eligible && _counted < countdownLength) {
      _counted += const Duration(seconds: 1);
    }
    if (eligible && _counted >= countdownLength) {
      _commit();
    } else {
      _upNext();
    }
  }

  /// Calls resolve() once and caches it; the error, if any, reaches _commit.
  Future<Object?> _prefetch(NextUp next) =>
      _resolved ??= Future.sync(next.resolve)..ignore();

  /// The one way to the next episode: bar button, card button, countdown end
  /// and completion. Pops with the resolved answer if this route is still on top.
  Future<void> _commit({bool forced = false}) async {
    final next = _next;
    if (next == null || _committed || !mounted) return;
    final token = ++_token;
    _countdown?.cancel();
    _countdown = null;
    setState(() {
      _committed = true;
      _forced = forced;
      _resolving = true;
    });
    _nextBar.value++;
    _player.pause().catchError((Object e) => debugPrint('pause: $e'));
    Object? result;
    var ok = false;
    try {
      result = await _prefetch(next);
      ok = true;
    } catch (e) {
      debugPrint('up next resolve: $e');
    }
    // media_kit's fullscreen is a route of its own above this one.
    if (ok && mounted && _video.currentState?.isFullscreen() == true) {
      await _video.currentState?.exitFullscreen();
    }
    if (!mounted || token != _token) return;
    if (ok && ModalRoute.of(context)?.isCurrent == true) {
      popForNext(context, result);
      return;
    }
    // Failed (or covered by another route): hide the card so nothing retries
    // by itself; the bar button tries again.
    setState(() {
      if (!ok) _resolved = null;
      _committed = _forced = _resolving = false;
      _dismissed = true;
      _counted = Duration.zero;
    });
    _nextBar.value++;
    _upNext();
  }

  void _setAutoplay(bool on) {
    setState(() {
      settings.autoplayNext = on;
      _counted = Duration.zero;
    });
    _upNext();
  }

  bool get _stoppedEarly => stoppedEarly(
    started: _started,
    error: _lastPlaybackError != null,
    position: _pos,
    duration: _player.state.duration,
    buffer: _player.state.buffer,
  );

  void _fatalError() {
    if (mounted) {
      setState(() {
        _error = 'playback';
        _panel = false;
      });
      _endEpisode();
    }
  }

  /// Starts a buffering episode: Starting when [opening], else a stall.
  void _beginEpisode({required bool opening}) {
    _endTimers();
    _opening = opening;
    _since = DateTime.now();
    _lastProgress = null;
    _status = null;
    _statusAt = null;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    // A stall's panel appears at 600 ms, not at the next tick.
    if (!opening) {
      _reveal = Timer(const Duration(milliseconds: 600), () {
        if (mounted) setState(() {});
      });
    }
    _poll();
  }

  void _endEpisode() {
    final since = _since;
    if (since != null) {
      // Device measurement (adb logcat -s flutter): time to first frame, stall length.
      final kind = _error != null ? 'failed' : (_opening ? 'start' : 'stall');
      final ms = DateTime.now().difference(since).inMilliseconds;
      debugPrint('flick-metric $kind $ms ms');
    }
    _endTimers();
    _opening = false;
    _since = null;
    if (mounted) setState(() {});
  }

  void _endTimers() {
    _ticker?.cancel();
    _reveal?.cancel();
  }

  /// Advances the episode's wait and refreshes the torrent status and network state.
  void _poll() {
    if (!mounted || _since == null) return;
    setState(() {});
    networkOnline().then((on) {
      if (mounted) setState(() => _online = on);
    });
    final t = widget.torrent;
    t?.engine.status(t.id).then((s) {
      if (!mounted || s == null) return;
      setState(() {
        _status = (peers: s.peers, rate: s.rate);
        _statusAt = DateTime.now();
      });
    }, onError: (Object e) => debugPrint('torrent status: $e'));
  }

  BufferView get _bufferView {
    final since = _since, status = _status, statusAt = _statusAt;
    final now = DateTime.now();
    final BufferView view = since == null
        ? (
            phase: BufferPhase.hidden,
            progress: null,
            stats: null,
            offerSwitch: false,
          )
        : bufferView(
            started: !_opening,
            buffering: _player.state.buffering,
            waited: now.difference(since),
            percent: _player.state.bufferingPercentage,
            lastProgress: _lastProgress,
            online: _online,
            repeatedStalls: _pauseWait.repeated,
            torrent: status == null || statusAt == null
                ? null
                : (
                    peers: status.peers,
                    rate: status.rate,
                    age: now.difference(statusAt),
                  ),
          );
    _lastProgress = view.progress;
    return view;
  }

  Future<void> _checkStopped() async {
    try {
      final idle = await (_player.platform as NativePlayer).getProperty(
        'idle-active',
      );
      if (mounted && idle == 'yes' && _stoppedEarly) _fatalError();
    } catch (e) {
      debugPrint('player stop check: $e');
    }
  }

  void _showError(Object e) {
    debugPrint('player: $e');
    final message = '$e'.toLowerCase();
    if (message.contains('subtitle') || message.contains('sub-add')) {
      // _choose reports a file that failed to load; these never end playback.
      if (_pending != null) _applicationError = '$e';
      return;
    }
    _lastPlaybackError = '$e';
    // Before the first frame too, only a stopped player is a failure.
    _checkStopped();
    // mpv logs the error before it goes idle and media_kit reports no
    // stop after a failed load, so look again shortly.
    if (!_started) {
      for (final s in [1, 3]) {
        Timer(Duration(seconds: s), () {
          if (mounted && !_started && _lastPlaybackError != null) {
            _checkStopped();
          }
        });
      }
    }
  }

  Future<void> _fetchSubtitles() async {
    if (_loading || _fetched) return;
    final p = widget.playback;
    if (p == null) return;
    setState(() {
      _loading = true;
      _catalogueError = null;
    });
    try {
      final entries = await addons.subtitles(
        p.type,
        p.videoId,
        hash: widget.hash,
        size: widget.size,
        filename: widget.filename,
      );
      if (!mounted) return;
      setState(() {
        _catalogue = entries;
        _fetched = true;
      });
    } catch (e) {
      if (mounted) setState(() => _catalogueError = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _autoPick();
      }
    }
  }

  List<_Caption> get _captions {
    final result = <_Caption>[];
    for (final t in embeddedSubtitles(
      _player.state.tracks.subtitle,
      _added.values,
    )) {
      result.add((
        track: t,
        url: null,
        lang: subtitleLanguage(t.language ?? 'und'),
        label:
            t.title ??
            '${subtitleLanguageName(t.language ?? 'und')} · Embedded',
        detail: 'Embedded',
      ));
    }
    final seen = <String>{};
    for (final s in [...widget.subtitles, ..._catalogue]) {
      if (!seen.add(s.url)) continue;
      final lang = subtitleLanguage(s.lang);
      // Subtitle records carry no release metadata; only show a supplied URL filename.
      final uri = Uri.tryParse(s.url);
      final name = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : '';
      final filename = RegExp(
        r'\.(srt|ass|ssa|vtt|sub)$',
        caseSensitive: false,
      ).hasMatch(name);
      result.add((
        // Until _choose loads the file, the URL stands in for its track id.
        track: SubtitleTrack(_added[s.url] ?? s.url, s.id, s.lang),
        url: s.url,
        lang: lang,
        label: filename
            ? name
            : '${subtitleLanguageName(lang)} · File ${result.where((c) => c.lang == lang).length + 1}',
        detail: filename ? subtitleLanguageName(lang) : '',
      ));
    }
    return result;
  }

  void _autoPick() {
    if (!mounted ||
        !_started ||
        _manual ||
        _autoPicked ||
        widget.playback == null ||
        _pending != null) {
      return;
    }
    final lang = subtitleLanguage(
      PlatformDispatcher.instance.locale.languageCode,
    );
    final streamMatch = widget.subtitles.any(
      (s) => subtitleLanguage(s.lang) == lang,
    );
    if (!streamMatch && (_loading || !_fetched)) return;
    _autoPicked = true;
    final audio = _player.state.track.audio;
    if (subtitleLanguage(audio.language ?? '') == lang) return;
    final selected = _player.state.track.subtitle;
    if (selected.id != 'auto' && selected.id != 'no') return;
    final matching = _captions.where((c) => c.lang == lang).toList();
    // Stream entries take precedence over addon and embedded entries.
    final streamUrls = widget.subtitles.map((s) => s.url).toSet();
    final preferred = matching
        .where((c) => streamUrls.contains(c.url))
        .toList();
    final external = matching.where((c) => c.url != null).toList();
    if (preferred.isNotEmpty || external.isNotEmpty) {
      _choose(
        preferred.isNotEmpty ? preferred.first : external.first,
        automatic: true,
      );
    } else {
      setState(
        () => _notice = 'No ${subtitleLanguageName(lang)} subtitles found',
      );
    }
  }

  Future<void> _choose(_Caption caption, {bool automatic = false}) async {
    if (!automatic) _manual = true;
    if (_pending != null) return;
    final previous = _selected ?? _player.state.track.subtitle;
    _applicationError = null;
    setState(() {
      _selected = previous;
      _pending = caption.url ?? caption.track.id;
      _subtitleError = null;
      _notice = null;
    });
    try {
      var track = caption.track;
      final url = caption.url;
      if (url != null && !_added.containsKey(url)) {
        final text = await _subtitleText(url);
        await _player.setSubtitleTrack(
          SubtitleTrack.data(
            text,
            title: track.title,
            language: track.language,
          ),
        );
        final mpv = _player.platform as NativePlayer;
        final sid = addedSubtitle(
          await mpv.getProperty('track-list'),
          await mpv.getProperty('sid'),
          _added.values,
        );
        if (sid == null) throw StateError('Subtitle did not load');
        _added[url] = sid;
        track = SubtitleTrack(sid, track.title, track.language);
      } else {
        await _player.setSubtitleTrack(track);
      }
      if (_applicationError != null) throw StateError(_applicationError!);
      if (automatic && _manual) {
        await _player.setSubtitleTrack(previous);
        return;
      }
      if (!mounted) return;
      setState(() {
        _selected = track;
        _failed = null;
        _language = caption.lang;
      });
      if (!automatic) HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint('subtitle: $e');
      try {
        await _player.setSubtitleTrack(previous);
      } catch (e) {
        debugPrint('subtitle restore: $e');
      }
      if (mounted) {
        setState(() {
          _selected = previous;
          _failed = caption;
          _subtitleError = 'Couldn’t load this subtitle file';
        });
      }
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  /// Fetched here rather than by mpv, which would send the stream's request
  /// headers (e.g. a debrid token) to the third-party subtitle host.
  Future<String> _subtitleText(String url) async {
    if (_subtitleFiles[url] case final text?) return text;
    final r = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode ~/ 100 != 2) throw StateError('HTTP ${r.statusCode}');
    String text;
    try {
      text = utf8.decode(r.bodyBytes);
    } on FormatException {
      text = latin1.decode(r.bodyBytes); // older .srt files are often Latin-1
    }
    return _subtitleFiles[url] = text;
  }

  void _togglePanel([bool? open]) {
    _languageSearch.clear();
    setState(() {
      _panel = open ?? !_panel;
      _languages = false;
      _search = '';
    });
    if (_panel) _fetchSubtitles();
    // Closing the panel releases a held countdown or a completion waiting on it.
    _upNext();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (_panel ? _headingFocus : _entryFocus).requestFocus();
    });
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      setState(() {
        _error = null;
        // Reloading the file drops the subtitle files added to it.
        _selected = null;
      });
      _added.clear();
      _lastPlaybackError = null;
      await _open(_pos);
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _init() async {
    final mpv = _player.platform as NativePlayer;
    // Buffer hard up front and after a stall instead of stuttering.
    for (final (k, v) in [
      ('demuxer-max-bytes', '${128 * 1024 * 1024}'),
      ('demuxer-max-back-bytes', '${16 * 1024 * 1024}'),
      ('cache-pause-initial', 'yes'),
      // Resumes sooner; _onBuffering raises it if stalls repeat.
      ('cache-pause-wait', '${_pauseWait.seconds}'),
      // The torrent server holds a request open until its piece downloads, so outwait
      // media_kit's 5 s network-timeout, and reconnect at the current offset if it drops an idle one.
      ('network-timeout', widget.torrent != null ? '120' : '30'),
      (
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
      ),
    ]) {
      if (!mounted) return;
      await mpv.setProperty(k, v);
    }
    if (!mounted) return;
    await _open(_pos);
  }

  Future<void> _open(Duration start) {
    _openedAt = start;
    _beginEpisode(opening: true);
    return _player.open(
      Media(widget.source, start: start, httpHeaders: widget.headers),
    );
  }

  void _onBuffering(bool buffering) {
    if (_pauseWait.buffering(buffering, DateTime.now())) {
      (_player.platform as NativePlayer)
          .setProperty('cache-pause-wait', '${_pauseWait.seconds}')
          .catchError((Object e) => debugPrint('cache-pause-wait: $e'));
    }
    if (_started && !_opening) {
      if (buffering && _since == null) _beginEpisode(opening: false);
      if (!buffering && _since != null) _endEpisode();
    }
  }

  @override
  void dispose() {
    _entryFocus.dispose();
    _headingFocus.dispose();
    _languageSearch.dispose();
    for (final controller in _scrolls.values) {
      controller.dispose();
    }
    _endTimers();
    _countdown?.cancel();
    _token++;
    _nextBar.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    if (--_live == 0) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = _next;
    final bar = <Widget>[
      _TopBar(
        title: widget.playback?.title ?? widget.title,
        subtitle: widget.playback?.subtitle,
        buffer: _BufferAhead(_player),
        subtitles: Semantics(
          label: 'Subtitles, $_activeSubtitle',
          button: true,
          child: TextButton.icon(
            focusNode: _entryFocus,
            style: TextButton.styleFrom(
              fixedSize: const Size(96, 48),
              padding: EdgeInsets.zero,
              foregroundColor: FlickTokens.textPrimary,
              textStyle: FlickText.button,
            ),
            onPressed: _togglePanel,
            icon: const Icon(Icons.closed_caption_outlined, size: 20),
            label: const Text('Subtitles'),
          ),
        ),
      ),
    ];
    final theme = MaterialVideoControlsThemeData(
      topButtonBar: bar,
      topButtonBarMargin: EdgeInsets.zero,
      buttonBarHeight: 64,
      bottomButtonBar: [
        const MaterialPositionIndicator(),
        const Spacer(),
        IconButton(
          tooltip: 'Subtitles',
          onPressed: _togglePanel,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.closed_caption_outlined),
        ),
        if (widget.next != null)
          ListenableBuilder(
            listenable: _nextBar,
            builder: (_, _) => _next == null
                ? const SizedBox.shrink()
                : NextEpisodeButton(
                    onPressed: _resolving ? null : () => _commit(forced: true),
                  ),
          ),
        const MaterialFullscreenButton(),
      ],
      seekBarColor: Colors.white.withValues(alpha: 0.2),
      seekBarBufferColor: Colors.white.withValues(alpha: 0.45),
      seekBarPositionColor: FlickTokens.accent,
      seekBarThumbColor: FlickTokens.accent,
      // Addon playback shows BufferingPanel instead.
      bufferingIndicatorBuilder: (_) => const SizedBox.shrink(),
    );
    return PopScope(
      canPop: !_panel,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !_panel) return;
        if (_languages) {
          setState(() {
            _languages = false;
            _search = '';
          });
        } else {
          _togglePanel(false);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MaterialVideoControlsTheme(
          normal: theme,
          fullscreen: theme,
          child: Stack(
            children: [
              ExcludeFocus(
                excluding: _panel,
                child: ExcludeSemantics(
                  excluding: _panel,
                  child: Video(
                    key: _video,
                    controller: _controller,
                    // media_kit's default shows the bars and unlocks rotation.
                    onExitFullscreen: _immersive,
                  ),
                ),
              ),
              if (_error == null)
                Positioned.fill(
                  child: ExcludeFocus(
                    excluding: _panel,
                    child: ExcludeSemantics(
                      excluding: _panel,
                      child: BufferingPanel(
                        view: _bufferView,
                        onSwitch: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              if (next != null)
                Positioned.fill(
                  child: SafeArea(
                    child: Padding(
                      // Clears the 64 dp bottom bar whether it shows or not:
                      // media_kit keeps the controls' visibility private.
                      padding: const EdgeInsets.only(
                        right: FlickTokens.railGap,
                        bottom: 64 + FlickTokens.railGap,
                      ),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: ExcludeFocus(
                          excluding: _panel,
                          child: ExcludeSemantics(
                            excluding: _panel,
                            child: UpNextCard(
                              view: _upNextView(next, _player.state.position),
                              episode: next.episode,
                              autoplay: settings.autoplayNext,
                              onNext: _commit,
                              onDismiss: () {
                                setState(() => _dismissed = true);
                                _upNext();
                              },
                              onAutoplay: _setAutoplay,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_error != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: FlickTokens.background,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(FlickTokens.pageGutter),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.report_outlined,
                              color: context.flick.danger,
                            ),
                            const SizedBox(height: 12),
                            const Text("Couldn't play this video"),
                            const SizedBox(height: 8),
                            const Text(
                              "The source didn't respond or the file can't be played.",
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: _retrying ? null : _retry,
                                  child: const Text('Retry'),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(48, 48),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Choose another source'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (_panel)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () => _togglePanel(false),
                  ),
                ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: .5,
                    heightFactor: 1,
                    child: AnimatedSlide(
                      offset: _panel ? Offset.zero : const Offset(1, 0),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : FlickTokens.sheetDuration,
                      curve: _panel
                          ? FlickTokens.curveIn
                          : FlickTokens.curveOut,
                      child: IgnorePointer(
                        ignoring: !_panel,
                        child: ExcludeFocus(
                          excluding: !_panel,
                          child: ExcludeSemantics(
                            excluding: !_panel,
                            child: _tracksPanel(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _activeSubtitle {
    final track = _selected ?? _player.state.track.subtitle;
    return track.id == 'no' || track.id == 'auto'
        ? 'Off'
        : subtitleLanguageName(track.language ?? 'und');
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    String? detail,
    bool pending = false,
    double height = 48,
  }) => Semantics(
    checked: selected,
    inMutuallyExclusiveGroup: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 3,
                child: selected
                    ? const ColoredBox(color: FlickTokens.activeMarker)
                    : null,
              ),
              const SizedBox(width: 17),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FlickText.body,
                      ),
                      if (pending || (detail != null && detail.isNotEmpty))
                        Text(
                          pending ? 'Opening subtitles…' : detail!,
                          style: FlickText.metadata,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Center(
                child: Icon(
                  selected
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected
                      ? FlickTokens.activeMarker
                      : FlickTokens.textSecondary,
                ),
              ),
              const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _message(
    IconData icon,
    String text,
    String action,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: FlickTokens.textSecondary),
        Semantics(liveRegion: true, child: Text(text, style: FlickText.body)),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onTap,
          child: Text(action),
        ),
      ],
    ),
  );

  Widget _tracksPanel() {
    final captions = _captions;
    final groups = <String, List<_Caption>>{};
    for (final caption in captions) {
      groups.putIfAbsent(caption.lang, () => []).add(caption);
    }
    final language = _language ?? (groups.isEmpty ? null : groups.keys.first);
    final files = groups[language] ?? const <_Caption>[];
    final active = _selected ?? _player.state.track.subtitle;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FlickTokens.stateDuration;
    final audio = _player.state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    return FocusScope(
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: Material(
          color: FlickTokens.surface1,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(FlickTokens.modalRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 72,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_languages)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: IconButton(
                          tooltip: 'Back to subtitles',
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          onPressed: () => setState(() {
                            _languages = false;
                            _search = '';
                          }),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          _languages ? 0 : 20,
                          16,
                          0,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Focus(
                              focusNode: _headingFocus,
                              child: Semantics(
                                header: true,
                                child: Text(
                                  _languages ? 'Languages' : 'Subtitles',
                                  style: FlickText.railHeading,
                                ),
                              ),
                            ),
                            if (!_languages)
                              const Text(
                                'OpenSubtitles v3',
                                style: FlickText.metadata,
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: IconButton(
                        tooltip: 'Close subtitles',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: () => _togglePanel(false),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: duration,
                  child: _languages
                      ? Column(
                          key: const ValueKey('languages'),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: SizedBox(
                                height: 52,
                                child: TextField(
                                  controller: _languageSearch,
                                  onChanged: (s) => setState(() => _search = s),
                                  decoration: const InputDecoration(
                                    labelText: 'Search languages',
                                    prefixIcon: Icon(Icons.search),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                children: [
                                  for (final lang in groups.keys)
                                    if (subtitleLanguageName(lang)
                                        .toLowerCase()
                                        .contains(_search.toLowerCase()))
                                      _choice(
                                        label:
                                            '${subtitleLanguageName(lang)} · ${groups[lang]!.length} files',
                                        selected: lang == language,
                                        onTap: () {
                                          setState(() {
                                            _language = lang;
                                            _languages = false;
                                            _search = '';
                                          });
                                          HapticFeedback.selectionClick();
                                        },
                                      ),
                                  if (!groups.keys.any(
                                    (l) => subtitleLanguageName(l)
                                        .toLowerCase()
                                        .contains(_search.toLowerCase()),
                                  ))
                                    _message(
                                      Icons.search,
                                      'No matching languages',
                                      'Clear search',
                                      () {
                                        _languageSearch.clear();
                                        setState(() => _search = '');
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          key: const ValueKey('files'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _choice(
                              label: 'Off',
                              selected:
                                  active.id == 'no' || active.id == 'auto',
                              onTap: _pending == null
                                  ? () => _choose((
                                      track: SubtitleTrack.no(),
                                      url: null,
                                      lang: language ?? 'und',
                                      label: 'Off',
                                      detail: '',
                                    ))
                                  : null,
                            ),
                            SizedBox(
                              height: 48,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                ),
                                onPressed: () =>
                                    setState(() => _languages = true),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Language',
                                      style: FlickText.metadata,
                                    ),
                                    const Spacer(),
                                    Flexible(
                                      child: Text(
                                        language == null
                                            ? 'Choose language'
                                            : subtitleLanguageName(language),
                                        overflow: TextOverflow.ellipsis,
                                        style: FlickText.button,
                                      ),
                                    ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                              child: Text(
                                language == null
                                    ? 'Subtitle files'
                                    : '${subtitleLanguageName(language)} · ${files.length} files',
                                style: FlickText.metadata,
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                key: ValueKey(language),
                                controller: _scrolls.putIfAbsent(
                                  language ?? '',
                                  ScrollController.new,
                                ),
                                children: [
                                  if (_loading) ...[
                                    for (var i = 0; i < 2; i++)
                                      const Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 16,
                                        ),
                                        child: Skeleton(height: 40),
                                      ),
                                  ],
                                  if (_catalogueError != null)
                                    _message(
                                      Icons.error_outline,
                                      _catalogueError!,
                                      'Retry',
                                      _fetchSubtitles,
                                    ),
                                  if (_subtitleError != null)
                                    _message(
                                      Icons.error_outline,
                                      _subtitleError!,
                                      'Retry',
                                      () {
                                        if (_failed case final caption?) {
                                          _choose(caption);
                                        }
                                      },
                                    ),
                                  if (_notice != null)
                                    _message(
                                      Icons.language,
                                      _notice!,
                                      'Choose language',
                                      () => setState(() => _languages = true),
                                    ),
                                  if (!_loading &&
                                      _catalogueError == null &&
                                      captions.isEmpty)
                                    _message(
                                      Icons.closed_caption_outlined,
                                      'No subtitles found for this episode',
                                      'Retry',
                                      () {
                                        _fetched = false;
                                        _fetchSubtitles();
                                      },
                                    ),
                                  for (final caption in files)
                                    _choice(
                                      label: caption.label,
                                      detail: caption.detail,
                                      height: 72,
                                      pending:
                                          _pending ==
                                          (caption.url ?? caption.track.id),
                                      selected: active.id == caption.track.id,
                                      onTap: _pending == null
                                          ? () => _choose(caption)
                                          : null,
                                    ),
                                  if (audio.isNotEmpty) ...[
                                    const Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        20,
                                        16,
                                        20,
                                        8,
                                      ),
                                      child: Text(
                                        'Audio',
                                        style: FlickText.railHeading,
                                      ),
                                    ),
                                    for (final track in audio)
                                      _choice(
                                        label:
                                            track.title ??
                                            subtitleLanguageName(
                                              track.language ?? 'und',
                                            ),
                                        selected:
                                            track.id ==
                                            _player.state.track.audio.id,
                                        onTap: () async {
                                          try {
                                            await _player.setAudioTrack(track);
                                          } catch (e) {
                                            if (mounted) {
                                              setState(
                                                () => _subtitleError =
                                                    friendlyError(e),
                                              );
                                            }
                                          }
                                        },
                                      ),
                                  ],
                                  if (_next != null)
                                    SwitchListTile(
                                      value: settings.autoplayNext,
                                      onChanged: _resolving
                                          ? null
                                          : _setAutoplay,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 20,
                                          ),
                                      title: const Text(
                                        'Autoplay next episode',
                                        style: FlickText.body,
                                      ),
                                      thumbColor:
                                          WidgetStateProperty.resolveWith(
                                            (s) =>
                                                s.contains(WidgetState.selected)
                                                ? FlickTokens.onAccent
                                                : FlickTokens.textSecondary,
                                          ),
                                      trackColor:
                                          WidgetStateProperty.resolveWith(
                                            (s) =>
                                                s.contains(WidgetState.selected)
                                                ? FlickTokens.accent
                                                : FlickTokens.surface2,
                                          ),
                                      trackOutlineColor:
                                          WidgetStateProperty.resolveWith(
                                            (s) =>
                                                s.contains(WidgetState.selected)
                                                ? FlickTokens.accent
                                                : FlickTokens.outline,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                            Semantics(
                              liveRegion: true,
                              label: _pending != null
                                  ? 'Opening subtitles…'
                                  : 'Subtitles: $_activeSubtitle',
                              child: const SizedBox.shrink(),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How far the buffer runs ahead of the playhead.
class _BufferAhead extends StatelessWidget {
  const _BufferAhead(this.player);
  final Player player;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: player.stream.buffer,
    builder: (_, _) {
      final ahead = player.state.buffer - player.state.position;
      final s = ahead.isNegative ? Duration.zero : ahead;
      return Text.rich(
        TextSpan(
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          children: [
            const TextSpan(text: 'Buffered '),
            TextSpan(
              text:
                  '${s.inMinutes}:${(s.inSeconds % 60).toString().padLeft(2, '0')}',
              style: monoStyle.copyWith(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    },
  );
}

/// Back target, title block (with buffer readout) and the subtitles entry over a soft scrim.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    this.subtitle,
    required this.buffer,
    this.subtitles,
  });
  final String title;
  final String? subtitle;
  final Widget buffer;
  final Widget? subtitles;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB3000000), Color(0x00000000)],
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            SizedBox.square(
              dimension: 48,
              child: BackButton(
                color: Colors.white,
                style: IconButton.styleFrom(minimumSize: const Size.square(48)),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: subtitle == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(color: Colors.white),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(color: Colors.white70),
                    ),
                  buffer,
                ],
              ),
            ),
            ?subtitles,
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
