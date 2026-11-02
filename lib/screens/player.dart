import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../kit/route.dart';
import '../kit/focus.dart';
import '../history.dart';
import '../addons.dart' show Subtitle;
import '../playback.dart';
import '../pip.dart';
import '../live.dart';
import '../queue.dart';
import '../kit/sidebar.dart';
import '../kit/sheet.dart';
import 'player_feedback.dart';
import 'live_queue.dart';
import 'movie_queue.dart';
import '../player_keys.dart' show LiveSeekRange, liveSeekRange;
import '../stall.dart';
import '../state.dart';
import '../subtitles.dart';
import '../offline_subtitles.dart';
import '../theme.dart';
import '../torrent.dart';
import '../upnext.dart';
import '../widgets.dart';
import 'buffering.dart';
import 'seek.dart';
import 'speed.dart';
import 'subtitle_adjustments.dart';
import 'offline_subtitles.dart';
import 'upnext.dart';
import 'tv_player.dart';
import 'volume.dart';

typedef Caption = ({
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

/// Match language rather than a track ID, which can change between files/opens.
AudioTrack? preferredAudioTrack(List<AudioTrack> tracks, String? preference, {AudioTrack? choice}) {
  final audio = tracks.where((t) => t.id != 'auto' && t.id != 'no');
  final language = subtitleLanguage((choice == null ? preference : choice.language) ?? 'und');
  if (choice != null) {
    final exact = audio.where((t) => t.id == choice.id && subtitleLanguage(t.language ?? 'und') == language).firstOrNull;
    if (exact != null) return exact;
  }
  if (language.isEmpty || language == 'und') {
    return null;
  }
  return audio.where((t) => subtitleLanguage(t.language ?? 'und') == language).firstOrNull;
}

/// A per-video choice wins on Retry; persisted preferences match fresh tracks by language.
Caption? preferredCaption(List<Caption> captions, {
  String? preference, Caption? choice, required String deviceLanguage,
  required String? audioLanguage, required String selectedId, Set<String> streamUrls = const {},
  String? savedUrl,
}) {
  if (choice?.track.id == 'no' || choice == null && preference == 'off') {
    return (track: SubtitleTrack.no(), url: null, lang: choice?.lang ?? subtitleLanguage(deviceLanguage), label: 'Off', detail: '');
  }
  if (choice != null) {
    final match = captions.where((c) => choice.url != null ? c.url == choice.url : c.track.id == choice.track.id).firstOrNull;
    if (match != null) return match;
  }
  if (choice == null && savedUrl != null) {
    final saved = captions.where((c) => c.url == savedUrl).firstOrNull;
    if (saved != null) return saved;
  }
  final language = subtitleLanguage(choice?.lang ?? preference ?? deviceLanguage);
  if (preference == null && choice == null &&
      (subtitleLanguage(audioLanguage ?? '') == language || selectedId != 'auto' && selectedId != 'no')) { return null; }
  final matching = captions.where((c) => c.lang == language);
  return matching.where((c) => streamUrls.contains(c.url)).firstOrNull ??
    matching.where((c) => c.url != null).firstOrNull ?? matching.firstOrNull;
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
  bool live = false,
}) {
  if (!started) return true;
  if (live) return true;
  if (duration <= Duration.zero || position >= duration * 0.9) return false;
  return error && buffer - position < const Duration(seconds: 1);
}

/// media_kit's top and bottom button bars (`buttonBarHeight`), and a margin the
/// height of its seek bar (`seekBarContainerHeight`) above the bottom one, so a
/// tap aimed at the seek bar never seeks by 10 s.
const _barHeight = 64.0, _seekBarHeight = 36.0;

/// Width of the back 10 s · play/pause · forward 10 s group in the middle of
/// the player.
const primaryBarWidth = FlickTokens.grid * 60;

/// Half the width of the player's middle, where taps never seek: a third of
/// the width, and never narrower than the button group plus a margin, so a
/// double tap on a button can't seek as well. [skew] is how far uneven side
/// insets (a display cutout in media_kit's fullscreen) can move the group.
double seekMiddle(double width, {double skew = 0}) {
  const group = primaryBarWidth + FlickTokens.grid * 8;
  return (width / 3 > group ? width / 3 : group) / 2 + skew;
}

/// Which way a double tap at [p] seeks (design/seek.md): -1 left, 1 right, 0 in
/// the middle ([seekMiddle]) or the [top]/[bottom] control bands.
int seekZone(
  Offset p,
  Size s, {
  required double top,
  required double bottom,
  double skew = 0,
}) {
  if (p.dy < top || p.dy > s.height - bottom) return 0;
  final half = seekMiddle(s.width, skew: skew);
  if (p.dx < s.width / 2 - half) return -1;
  if (p.dx > s.width / 2 + half) return 1;
  return 0;
}

/// Where a ±[seconds] nudge lands: on from a seek still [pending], within the
/// video.
Duration nudgeTarget({
  required Duration position,
  Duration? pending,
  required Duration duration,
  required int seconds,
  Duration start = Duration.zero,
}) {
  final to = (pending ?? position) + Duration(seconds: seconds);
  if (to < start) return start;
  return to > duration ? duration : to;
}

/// One burst of ±10 s nudges (design/seek.md): where it will seek, and the
/// side and running total the ripple shows. The player seeks to [settle] once
/// the taps stop.
class SeekBurst {
  Duration? _target;
  int side = 0, total = 0;

  /// Adds a nudge; false (nothing to show) without a seekable interval.
  bool nudge(
    int seconds, {
    required Duration position,
    required Duration duration,
    Duration start = Duration.zero,
  }) {
    if (duration <= start) return false;
    _target = nudgeTarget(
      position: position,
      pending: _target,
      duration: duration,
      seconds: seconds,
      start: start,
    );
    final s = seconds.sign;
    total = s == side ? total + seconds.abs() : seconds.abs();
    side = s;
    return true;
  }

  /// Ends the burst: where to seek, or null. [total] stays for the fade-out.
  Duration? settle([DateTime? now]) {
    final target = _target;
    _target = null;
    side = 0;
    if (target != null) {
      _landing = target;
      _settledAt = now ?? DateTime.now();
    }
    return target;
  }

  Duration? _landing;
  DateTime _settledAt = DateTime(0);

  /// Whether position report [p] is current. For a moment after a seek mpv can
  /// still report the time from before it, and the next burst must not count
  /// from that (found on the phone: taps 0.6 s apart lost 10 s on a torrent).
  /// Until a report lands near the target, or 2 s pass, others are stale.
  bool current(Duration p, [DateTime? now]) {
    final landing = _landing;
    if (landing == null) return true;
    final near = (p - landing).abs() <= const Duration(milliseconds: 1500);
    final late =
        (now ?? DateTime.now()).difference(_settledAt) >
        const Duration(seconds: 2);
    if (!near && !late) return false;
    _landing = null;
    return true;
  }
}

/// Which taps seek (design/seek.md). A tap is one pointer, still and short. A
/// double tap on a side opens a burst; while it's open every tap on that side
/// counts. A second pointer, a drag or a cancel voids the tap in progress.
class SeekTaps {
  int? _pointer;
  Offset _down = Offset.zero;
  Duration _downAt = Duration.zero;
  bool _void = false;
  Offset _lastUp = Offset.zero;
  Duration? _lastUpAt;
  int _lastZone = 0;

  void down(int pointer, Offset p, Duration t) {
    if (_pointer != null) {
      _void = true;
      return;
    }
    _pointer = pointer;
    _down = p;
    _downAt = t;
    _void = false;
  }

  void move(int pointer, Offset p) {
    if (pointer == _pointer && (p - _down).distance > kTouchSlop) _void = true;
  }

  void cancel(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    _lastUpAt = null;
  }

  /// The side to seek towards for this tap (-1, 1), or 0. [zone] is
  /// [seekZone] of the tap, [burst] the side of the open burst or 0.
  int up(
    int pointer,
    Offset p,
    Duration t, {
    required int zone,
    required int burst,
  }) {
    if (pointer != _pointer) return 0;
    _pointer = null;
    if (_void ||
        zone == 0 ||
        (p - _down).distance > kTouchSlop ||
        t - _downAt >= kLongPressTimeout) {
      _lastUpAt = null;
      return 0;
    }
    if (zone == burst) return zone;
    final last = _lastUpAt;
    if (last != null &&
        zone == _lastZone &&
        // Like Android: from the first release to the second press.
        _downAt - last <= kDoubleTapTimeout &&
        (p - _lastUp).distance <= kDoubleTapSlop) {
      _lastUpAt = null;
      return zone;
    }
    _lastUp = p;
    _lastUpAt = t;
    _lastZone = zone;
    return 0;
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    required this.title,
    required this.source,
    this.headers = const {},
    this.subtitles = const [],
    this.downloadId, this.offlineSubtitle,
    this.playback,
    this.start,
    this.filename,
    this.size,
    this.hash,
    this.torrent,
    this.next,
    this.live = false,
    this.resolveLive,
    this.liveEvent, this.liveChannel, this.liveClient, this.onStarted,
    super.key,
  });
  final Playback? playback;
  /// Explicit start for this open; Retry continues from the current position.
  final Duration? start;
  final bool live;
  final LiveEvent? liveEvent;
  final LiveChannel? liveChannel;
  final LiveClient? liveClient;
  final VoidCallback? onStarted;
  final Future<LiveSource> Function()? resolveLive;
  final String? filename, hash;
  final int? size;

  /// Shown when there is no [playback], e.g. for a pasted magnet link.
  final String title;
  final Map<String, String> headers;
  final List<Subtitle> subtitles;
  final String? downloadId;
  final OfflineSubtitle? offlineSubtitle;

  /// The torrent behind [source] when it is the engine's loopback stream.
  final ({TorrentEngine engine, int id})? torrent;

  /// The next episode, for Up Next; the route pops with its `resolve()` answer. Null for movies.
  final Future<NextUp?>? next;

  /// An addon stream URL, the local torrent stream server or a downloaded file.
  final String source;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late LiveEvent? _currentEvent = widget.liveEvent;
  late LiveChannel? _currentChannel = widget.liveChannel;
  bool _queueShowing = false, _movieAdvancing = false;
  final _queueProgress = MovieQueueProgress();
  String get _displayTitle => widget.live && _currentEvent != null
    ? '${_currentEvent!.name} · ${_currentChannel!.name}' : widget.playback?.title ?? widget.title;
  bool get _hasQueue => widget.playback?.type == 'movie' || widget.liveClient != null;
  late LiveSource _source = (url: widget.source, headers: widget.headers);
  final _player = Player(
    configuration: const PlayerConfiguration(bufferSize: 400 * 1024 * 1024),
  );
  late final _controller = VideoController(_player);
  final _pauseWait = PauseWait();
  final _subs = <StreamSubscription>[];
  bool _started = false;
  String? _error;
  bool _retrying = false;
  double _unmutedVolume = 100;
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
  bool _audioPicked = false, _audioPending = false, _autoPicking = false;
  int _trackGeneration = 0;
  AudioTrack? _audioChoice;
  Caption? _captionChoice;
  String? _catalogueError, _subtitleError, _notice, _language, _pending;
  String _search = '';
  final _languageSearch = TextEditingController();
  List<Subtitle> _catalogue = [];
  final _entryFocus = FocusNode();
  final _headingFocus = FocusNode();
  final _tvLanguageFocus = FocusNode(debugLabel: 'Subtitle language');
  final _tvLanguageChoice = FocusNode(debugLabel: 'Selected subtitle language');
  final _scrolls = <String, ScrollController>{};
  SubtitleTrack? _selected;
  Caption? _failed;
  String? _applicationError;
  String? _lastPlaybackError;
  // Subtitle file text and the mpv track id it was added as, by URL.
  final _subtitleFiles = <String, String>{};
  late OfflineSubtitle? _offlineSubtitle = widget.offlineSubtitle;
  final _added = <String, String>{};
  late SubtitleAppearance _appearance = settings.subtitleAppearance;
  late final _timing = SubtitleTiming((seconds) =>
      (_player.platform as NativePlayer).setProperty('sub-delay', '$seconds'));
  // open() resets state.position to 0 until mpv reports time-pos; Retry and the stop check use this instead.
  Duration _pos = Duration.zero;
  Timer? _checkpoint;
  Duration? _savedPosition;
  Duration _duration = Duration.zero;
  // ±10 s seek (design/seek.md): taps add up and seek once, 400 ms after the
  // last, so a torrent clears its piece deadlines once per burst.
  final _taps = SeekTaps();
  final _burst = SeekBurst();
  Timer? _seekTimer;
  // (side, total) of the open burst. A notifier: the layer also lives in
  // media_kit's fullscreen route, which this State's setState doesn't reach.
  final _seek = ValueNotifier<(int, int)>((0, 0));
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
  final _tvRefresh = ValueNotifier(0);
  final _controlNotice = ValueNotifier<String?>(null);
  final _liveRange = ValueNotifier<LiveSeekRange?>(null);
  final _video = GlobalKey<VideoState>();
  late final _pip = PictureInPicture(
    onStop: () => _player.pause().catchError(_showError),
  );
  bool get _androidPip =>
      !kIsWeb && !device.tv && defaultTargetPlatform == TargetPlatform.android;

  // Up Next pushes the next player before this one is disposed: only the last
  // one out restores the system bars and rotation.
  static int _live = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final playback = widget.playback;
    if (!widget.live && playback != null) {
      _pos = widget.start ?? history.position(playback.type, playback.videoId, scope: playback.scope);
      _checkpoint = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
    }
    _live++;
    _immersive();
    _pip.addListener(_pipChanged);
    if (_androidPip) _pip.init();
    _subs
      ..add(
        _player.stream.position.listen((p) {
          if (device.tv) _tvRefresh.value++;
          // Before the early return: a seek to the start must reset Up Next.
          _upNext(p);
          final position = watchPosition(p, started: _started, opening: _opening, completed: _completed);
          if (position != null && _burst.current(position)) _pos = position;
          if (p <= Duration.zero) return;
          _pauseWait.position(p, DateTime.now());
          if (!_started) {
            // Errors before playback started weren't fatal after all.
            _started = true;
            if (_queueProgress.started()) {
              widget.onStarted?.call();
              if (widget.onStarted == null && widget.playback?.type == 'movie') {
                final pending = movieQueue.items.where((m) => m.sameMovie(widget.playback!.videoId, null)).firstOrNull;
                if (pending != null) movieQueue.remove(pending);
              }
            }
            _lastPlaybackError = null;
            if (_error != null && mounted) setState(() => _error = null);
          }
          if (_opening && p != _openedAt) {
            _endEpisode();
            if (_player.state.buffering) _beginEpisode(opening: false);
          }
          _autoPick();
          _syncTiming();
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
          _syncTiming();
        }),
      )
      ..add(
        _player.stream.completed.listen((done) {
          _completed = done;
          _endedEarly = done && _stoppedEarly;
          if (_endedEarly) _fatalError();
          _upNext();
          if (widget.playback?.type == 'movie' && _queueProgress.completed(done: done,
              stoppedEarly: _endedEarly, failed: !_started || _opening || _error != null || _lastPlaybackError != null, hasNext: movieQueue.items.isNotEmpty,
              panelOpen: _queueShowing || _panel)) {
            if (mounted && !_queueShowing) _showQueue(context, automatic: true);
          }
        }),
      )
      ..add(
        _player.stream.playing.listen((playing) {
          if (!playing) _saveProgress();
          if (_androidPip) _pip.playing(playing);
          if (device.tv) _tvRefresh.value++;
          if (!playing && _lastPlaybackError != null) _checkStopped();
        }),
      )
      ..add(_player.stream.volume.listen((_) {
        if (device.tv) _tvRefresh.value++;
      }))
      ..add(
        _player.stream.duration.listen((d) {
          if (d > Duration.zero) _duration = d;
          if (device.tv) _tvRefresh.value++;
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
      ..add(
        _player.stream.buffer.listen((_) {
          if (device.tv) _tvRefresh.value++;
        }),
      )
      ..add(_player.stream.buffering.listen(_onBuffering))
      ..add(_player.stream.bufferingPercentage.listen((_) {
        if (mounted && _since != null) setState(() {});
      }))
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

  Future<void> _showQueue(BuildContext routeContext, {bool automatic = false}) async {
    if (_queueShowing || _movieAdvancing || _retrying) return;
    if (_panel) _togglePanel(false);
    _queueShowing = true;
    _tvRefresh.value++;
    try {
      if (widget.live) {
        final event = _currentEvent, channel = _currentChannel, client = widget.liveClient;
        if (event == null || channel == null || client == null) return;
        await showPlaybackSidebar<void>(routeContext, (_) => LiveQueuePanel(
          client: client, event: event, channel: channel, onSwitch: _switchLive));
      } else {
        final choice = await showPlaybackSidebar<MovieChoice>(routeContext, (_) => MovieQueueScreen(
          picking: true, initial: automatic ? movieQueue.items.firstOrNull : null));
        if (choice != null && mounted) await _leaveForMovie(choice);
      }
    } finally {
      _queueShowing = false;
      if (widget.liveClient != null) widget.liveClient!.cancelPrepared().catchError((_) {});
      if (mounted) _tvRefresh.value++;
      _resumeMovieQueue();
    }
  }

  void _resumeMovieQueue() {
    if (!_queueProgress.release(panelOpen: _panel || _queueShowing)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _completed && movieQueue.items.isNotEmpty && ModalRoute.of(context)?.isCurrent == true) {
        _showQueue(context, automatic: true);
      }
    });
  }

  Future<void> _leaveForMovie(MovieChoice choice) async {
    if (_movieAdvancing || !mounted) return;
    _movieAdvancing = true;
    try {
      await _player.pause();
      if (_video.currentState?.isFullscreen() == true) await _video.currentState?.exitFullscreen();
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        popForNext(context, MovieNext(choice));
      }
    } catch (e) { if (mounted) _showError(e); }
    finally { _movieAdvancing = false; }
  }

  Future<bool> _switchLive(LiveEvent event, LiveChannel channel) async {
    if (_retrying || !mounted) return false;
    setState(() => _retrying = true);
    var handedOff = false;
    try {
      final source = await widget.liveClient!.prepare(channel);
      if (!mounted || !_queueShowing) return false;
      await widget.liveClient!.commit(source);
      if (!mounted) return false;
      handedOff = true;
      _source = source;
      _currentEvent = event;
      _currentChannel = channel;
      _liveRange.value = null;
      _added.clear();
      _selected = null;
      _timing.clear();
      _lastPlaybackError = null;
      setState(() => _error = null);
      await _open(Duration.zero);
      _tvRefresh.value++;
      return true;
    } catch (e) {
      if (mounted && handedOff) _showError(e);
      return false;
    } finally { if (mounted) setState(() => _retrying = false); }
  }

  void _pipChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _enterPip() async {
    if (_video.currentState?.isFullscreen() == true) {
      await _video.currentState?.exitFullscreen();
    }
    if (!mounted) return;
    if (!await _pip.enter() && mounted) {
      _controlNotice.value = 'Picture-in-picture is unavailable. Check the app’s picture-in-picture permission in Android settings.';
    }
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
      if (!device.tv) _entryFocus.requestFocus();
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
    live: widget.live,
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
    debugPrint(widget.live ? 'live playback error' : 'player: $e');
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

  Future<void> _fetchSubtitles({bool force = false}) async {
    if (widget.live) return;
    if (_offlineSubtitle != null && !force) return;
    if (_loading || _fetched && !force) return;
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

  List<Caption> get _captions {
    final result = <Caption>[];
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
    for (final s in [?_offlineSubtitle?.subtitle, ...widget.subtitles, ..._catalogue]) {
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
        label: s.url == _offlineSubtitle?.subtitle.url ? 'Saved offline · ${_offlineSubtitle!.label}' : filename
            ? name
            : '${subtitleLanguageName(lang)} · File ${result.where((c) => c.lang == lang).length + 1}',
        detail: s.url == _offlineSubtitle?.subtitle.url ? 'Available offline' : filename ? subtitleLanguageName(lang) : '',
      ));
    }
    return result;
  }

  Future<void> _chooseAudio(AudioTrack track, {bool automatic = false}) async {
    if (_audioPending) return;
    final generation = _trackGeneration;
    setState(() { _audioPending = true; _audioPicked = true; });
    try {
      await _player.setAudioTrack(track);
      if (!mounted || generation != _trackGeneration) return;
      if (!automatic) {
        _audioChoice = track;
        await _rememberLanguage(track.language, audio: true);
      }
    } catch (e) {
      if (mounted && generation == _trackGeneration) setState(() => _subtitleError = friendlyError(e));
    } finally {
      if (mounted && generation == _trackGeneration) setState(() => _audioPending = false);
    }
  }

  Future<void> _rememberLanguage(String? language, {bool audio = false, bool off = false}) async {
    final normalized = subtitleLanguage(language ?? 'und');
    if (!off && (normalized.isEmpty || normalized == 'und')) {
      if (mounted) setState(() => _notice = 'Unknown language: this choice applies only to this video.');
      return;
    }
    try {
      if (audio) {
        await settings.saveAudioLanguage(normalized);
      } else {
        await settings.saveSubtitleLanguage(off ? 'off' : normalized);
      }
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not save this preference. Select the track again to retry.');
    }
  }

  Future<void> _autoPick() async {
    if (!mounted || !_started || _retrying || _autoPicking) return;
    final generation = _trackGeneration;
    _autoPicking = true;
    try {
      if (!_audioPicked && !_audioPending) {
        final selected = preferredAudioTrack(_player.state.tracks.audio, settings.audioLanguage, choice: _audioChoice);
        if (selected != null) await _chooseAudio(selected, automatic: true);
      }
      if (!mounted || generation != _trackGeneration) return;
      _autoPickSubtitle();
    } catch (e) {
      // A missing/broken preferred track must never prevent video playback.
      debugPrint('track preference: $e');
    } finally {
      _autoPicking = false;
    }
  }

  void _autoPickSubtitle() {
    if (!mounted ||
        !_started ||
        _manual ||
        _autoPicked ||
        _pending != null) {
      return;
    }
    final preference = settings.subtitleLanguage;
    final choice = _captionChoice;
    final locale = PlatformDispatcher.instance.locale.languageCode;
    final caption = preferredCaption(_captions, preference: preference, choice: choice,
      deviceLanguage: locale, audioLanguage: _player.state.track.audio.language,
      selectedId: _player.state.track.subtitle.id, streamUrls: widget.subtitles.map((s) => s.url).toSet(),
      savedUrl: _offlineSubtitle?.subtitle.url);
    if (caption != null) {
      _autoPicked = true;
      _choose(caption, automatic: true);
    } else if (_fetched || widget.playback == null) {
      _autoPicked = true;
      final language = subtitleLanguage(choice?.lang ?? preference ?? locale);
      if (!_captions.any((c) => c.lang == language)) {
        setState(() => _notice = 'No ${subtitleLanguageName(language)} subtitles found');
      }
    }
  }

  Future<void> _choose(Caption caption, {bool automatic = false}) async {
    if (!automatic) _manual = true;
    if (_pending != null) return;
    final generation = _trackGeneration;
    final previous = _selected ?? _player.state.track.subtitle;
    final previousTiming = _timing.key;
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
        if (!mounted || generation != _trackGeneration) return;
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
        if (!mounted || generation != _trackGeneration) return;
        if (sid == null) throw StateError('Subtitle did not load');
        _added[url] = sid;
        track = SubtitleTrack(sid, track.title, track.language);
      } else {
        await _player.setSubtitleTrack(track);
      }
      if (!mounted || generation != _trackGeneration) return;
      if (_applicationError != null) throw StateError(_applicationError!);
      if (automatic && _manual) {
        await _player.setSubtitleTrack(previous);
        return;
      }
      if (!mounted) return;
      await _timing.select(track.id == 'no' || track.id == 'auto' ? null :
          caption.url == null ? 'track:${track.id}' : 'file:${caption.url}');
      if (!mounted || generation != _trackGeneration) return;
      setState(() {
        _selected = track;
        _failed = null;
        _language = caption.lang;
      });
      if (!automatic) {
        _captionChoice = caption;
        HapticFeedback.selectionClick();
        await _rememberLanguage(caption.lang, off: track.id == 'no');
      }
    } catch (e) {
      if (!mounted || generation != _trackGeneration) return;
      debugPrint('subtitle: $e');
      try {
        await _player.setSubtitleTrack(previous);
        if (!mounted || generation != _trackGeneration) return;
        await _timing.select(previousTiming);
      } catch (e) {
        debugPrint('subtitle restore: $e');
      }
      if (mounted && generation == _trackGeneration) {
        setState(() {
          _selected = previous;
          _failed = caption;
          _subtitleError = 'Couldn’t load this subtitle file';
        });
      }
    } finally {
      if (mounted && generation == _trackGeneration) setState(() => _pending = null);
    }
  }

  String? get _timingKey {
    final track = _selected ?? _player.state.track.subtitle;
    if (track.id == 'no' || track.id == 'auto') return null;
    final url = _added.entries.where((entry) => entry.value == track.id).firstOrNull?.key;
    return url == null ? 'track:${track.id}' : 'file:$url';
  }

  void _syncTiming() {
    if (!mounted || !_started || _pending != null || _timing.key == _timingKey) return;
    _timing.select(_timingKey).then((_) {
      if (mounted) setState(() {});
    }).catchError((Object _) {
      if (mounted) setState(() => _subtitleError = 'Could not restore subtitle timing. Select the subtitle again to retry.');
    });
  }

  Future<void> _setSubtitleDelay(int value) async {
    await _timing.set(value);
    if (mounted) { setState(() {}); _tvRefresh.value++; }
  }

  Future<void> _setSubtitleAppearance(SubtitleAppearance value) async {
    if (!mounted) return;
    setState(() => _appearance = value);
    _video.currentState?.update(subtitleViewConfiguration: subtitleView(value));
    _tvRefresh.value++;
    await settings.saveSubtitleAppearance(value);
  }

  Widget _subtitleAdjustments() => SubtitleAdjustments(
    key: ValueKey(_timing.key),
    appearance: _appearance, delay: _timing.milliseconds,
    timingEnabled: _started && _pending == null && _timing.key != null,
    onDelay: _setSubtitleDelay, onAppearance: _setSubtitleAppearance,
  );

  Widget _offlineSubtitleControls() {
    final active = (_selected ?? _player.state.track.subtitle).id;
    final external = _captions.where((c) => c.url != null && c.url != _offlineSubtitle?.subtitle.url &&
      _added[c.url] == active).firstOrNull;
    return OfflineSubtitleControls(
      key: ValueKey(external?.url), saved: _offlineSubtitle != null,
      save: external == null || _pending != null ? null : () async {
        final text = await _subtitleText(external.url!);
        final saved = await downloads.saveSubtitle(widget.downloadId!, text: text, label: external.label, lang: external.lang);
        if (mounted) setState(() => _offlineSubtitle = saved);
      },
      remove: () async {
        await downloads.removeSubtitle(widget.downloadId!);
        if (mounted) setState(() => _offlineSubtitle = null);
      },
      findOnline: () => _fetchSubtitles(force: true),
    );
  }

  Future<void> _openTracks() async {
    // The track panel belongs to this route, below media_kit's separate fullscreen route.
    if (_video.currentState?.isFullscreen() == true) await _video.currentState?.exitFullscreen();
    if (mounted) _togglePanel();
  }

  /// Fetched here rather than by mpv, which would send the stream's request
  /// headers (e.g. a debrid token) to the third-party subtitle host.
  Future<String> _subtitleText(String url) async {
    if (_subtitleFiles[url] case final text?) return text;
    return _subtitleFiles[url] = url == _offlineSubtitle?.subtitle.url
        ? await _offlineSubtitle!.read() : await readExternalSubtitle(url);
  }

  void _togglePanel([bool? open]) {
    _languageSearch.clear();
    setState(() {
      _panel = open ?? !_panel;
      _languages = false;
      _search = '';
    });
    _tvRefresh.value++;
    if (_panel) _fetchSubtitles();
    // Closing the panel releases a held countdown or a completion waiting on it.
    _upNext();
    _resumeMovieQueue();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !device.tv && !_queueShowing) {
        (_panel ? _headingFocus : _entryFocus).requestFocus();
      }
    });
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      if (widget.resolveLive != null || widget.liveClient != null) {
        final source = widget.liveClient != null && _currentChannel != null
          ? await widget.liveClient!.resolve(_currentChannel!) : await widget.resolveLive!();
        if (!mounted) return;
        _source = source;
      }
      setState(() {
        _error = null;
        // Reloading the file drops the subtitle files added to it.
        _selected = null;
      });
      _added.clear();
      _lastPlaybackError = null;
      await _open(widget.live ? Duration.zero : _pos);
    } catch (e) {
      if (widget.live) {
        _fatalError();
      } else {
        _showError(e);
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  Future<void> _init() async {
    final mpv = _player.platform as NativePlayer;
    if (widget.live) {
      await mpv.observeProperty('demuxer-cache-state', (cache) async {
        if (!mounted) return;
        _liveRange.value = liveSeekRange(cache, _player.state.position);
        if (device.tv) _tvRefresh.value++;
      });
    }
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

  Future<void> _open(Duration start) async {
    _trackGeneration++;
    _started = false;
    _manual = false;
    _autoPicked = false;
    _audioPicked = false;
    _audioPending = false;
    _pending = null;
    _liveRange.value = null;
    _openedAt = start;
    _beginEpisode(opening: true);
    try {
      await _timing.select(null);
    } catch (_) {
      _subtitleError = 'Could not reset subtitle timing. Select the subtitle again to retry.';
    }
    if (!mounted) return;
    await _player.open(
      Media(_source.url, start: start, httpHeaders: _source.headers),
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
    _saveProgress();
    _checkpoint?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pip.removeListener(_pipChanged);
    _pip.dispose();
    _entryFocus.dispose();
    _headingFocus.dispose();
    _tvLanguageFocus.dispose();
    _tvLanguageChoice.dispose();
    _languageSearch.dispose();
    for (final controller in _scrolls.values) {
      controller.dispose();
    }
    _endTimers();
    _countdown?.cancel();
    _seekTimer?.cancel();
    _seek.dispose();
    _liveRange.dispose();
    _token++;
    _nextBar.dispose();
    _tvRefresh.dispose();
    _controlNotice.dispose();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _saveProgress();
  }

  void _saveProgress() {
    final p = widget.playback;
    // open() emits temporary zeroes; a failed open must leave the previous checkpoint intact.
    if (widget.live || p == null || !_started || _opening || _savedPosition == _pos) return;
    _savedPosition = _pos;
    history.save(WatchProgress(
      type: p.type, videoId: p.videoId, scope: p.scope, title: p.title, subtitle: p.subtitle, poster: p.poster,
      position: _pos, duration: _duration,
    )).catchError((Object e) {
      _savedPosition = null;
      debugPrint('viewing progress: $e');
    });
  }

  Future<void> _toggleMute() =>
      _setVolume(_player.state.volume > 0 ? 0 : _unmutedVolume);

  Future<void> _setVolume(double volume) async {
    if (volume == 0 && _player.state.volume > 0) {
      _unmutedVolume = _player.state.volume;
    }
    try {
      await _player.setVolume(volume);
    } catch (e) {
      debugPrint('volume: $e');
    }
  }

  Future<void> _showVolume(BuildContext context) async {
    await showFlickSheet<void>(context, (_) => VolumePanel(
        stream: _player.stream.volume,
        readVolume: () => _player.state.volume,
        onChanged: _setVolume,
        onMute: _toggleMute,
      ));
  }

  Future<void> _showSpeed(BuildContext context) async {
    final rate = await showFlickSheet<double>(context, (_) => SpeedPanel(rate: _player.state.rate));
    if (rate == null || !mounted) return;
    try {
      await _player.setRate(rate);
    } catch (e) {
      if (mounted) {
        _controlNotice.value = 'Could not change playback speed. Try again.';
      }
    }
  }

  void _nudge(int seconds) {
    final range = _liveRange.value;
    if (widget.live && range == null) return;
    // From _pos, not state.position: open() reports 0 until mpv seeks.
    final counted = _burst.nudge(
      seconds,
      position: _pos,
      duration: widget.live ? range!.end : _player.state.duration,
      start: widget.live ? range!.start : Duration.zero,
    );
    if (!counted) return;
    HapticFeedback.selectionClick();
    _seek.value = (_burst.side, _burst.total);
    _seekTimer?.cancel();
    _seekTimer = Timer(const Duration(milliseconds: 400), () {
      final target = _burst.settle();
      if (target != null) {
        _seekTo(target);
      }
      _seek.value = (0, _burst.total);
    });
  }

  Future<void> _seekTo(Duration target) async {
    if (widget.live) {
      final range = _liveRange.value;
      if (range == null) return;
      target = target < range.start ? range.start
          : target > range.end ? range.end : target;
    }
    _pos = target;
    await _player.seek(target).catchError(_showError);
  }

  /// media_kit's controls with the double-tap seek layer on top, in the page
  /// and in media_kit's fullscreen route. While a burst is open its side
  /// takes the taps itself, so media_kit doesn't flash the controls on each.
  Widget _controls(VideoState state) => ListenableBuilder(
    listenable: _pip,
    builder: (_, _) =>
        _pip.active ? const SizedBox.shrink() : _touchControls(state),
  );

  Widget _touchControls(VideoState state) => Stack(
    children: [
      MaterialVideoControls(state),
      Positioned.fill(
        child: IgnorePointer(
          ignoring: _panel,
          child: LayoutBuilder(
            builder: (context, box) {
              final size = box.biggest;
              final pad = MediaQuery.paddingOf(context);
              final top = _barHeight + pad.top;
              final bottom = _barHeight + _seekBarHeight + pad.bottom;
              final skew = (pad.left - pad.right).abs() / 2;
              final side = size.width / 2 - seekMiddle(size.width, skew: skew);
              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) =>
                    _taps.down(e.pointer, e.localPosition, e.timeStamp),
                onPointerMove: (e) => _taps.move(e.pointer, e.localPosition),
                onPointerCancel: (e) => _taps.cancel(e.pointer),
                onPointerUp: (e) {
                  final side = _taps.up(
                    e.pointer,
                    e.localPosition,
                    e.timeStamp,
                    zone: seekZone(
                      e.localPosition,
                      size,
                      top: top,
                      bottom: bottom,
                      skew: skew,
                    ),
                    burst: _seek.value.$1,
                  );
                  if (side != 0) _nudge(side * 10);
                },
                child: ValueListenableBuilder(
                  valueListenable: _seek,
                  builder: (_, seek, _) => Stack(
                    children: [
                      // Between the bands: the bars and the time stay readable.
                      Positioned(
                        left: 0,
                        right: 0,
                        top: top,
                        bottom: bottom,
                        child: IgnorePointer(
                          child: SeekRipple(side: seek.$1, seconds: seek.$2),
                        ),
                      ),
                      if (seek.$1 != 0)
                        Positioned(
                          left: seek.$1 < 0 ? 0 : size.width - side,
                          width: side,
                          top: top,
                          bottom: bottom,
                          child: const Listener(
                            behavior: HitTestBehavior.opaque,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      Positioned.fill(child: _controlFeedback()),
    ],
  );

  Widget _controlFeedback() => ValueListenableBuilder<String?>(
    valueListenable: _controlNotice,
    builder: (_, message, _) => message == null ? const SizedBox.shrink()
      : PlayerFeedback(message: message, onDismiss: () => _controlNotice.value = null),
  );

  @override
  Widget build(BuildContext context) {
    if (context.tv) return _buildTv();
    final next = _next;
    final bar = <Widget>[
      ListenableBuilder(listenable: _tvRefresh, builder: (_, _) => _TopBar(
        title: _displayTitle,
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
            onPressed: _openTracks,
            icon: const Icon(Icons.closed_caption_outlined, size: 20),
            label: const Text('Subtitles'),
          ),
        ),
      )),
    ];
    final theme = MaterialVideoControlsThemeData(
      displaySeekBar: !widget.live,
      topButtonBar: bar,
      topButtonBarMargin: EdgeInsets.zero,
      buttonBarHeight: _barHeight,
      // Stateless: media_kit never rebuilds its bars (see _nextBar).
      // A fixed width, so the group stays inside seekZone's middle.
      primaryButtonBar: [
        SizedBox(
          width: primaryBarWidth,
          child: ValueListenableBuilder(
            valueListenable: _liveRange,
            builder: (_, range, _) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SeekButton(_player, back: true,
                  onPressed: !widget.live || range != null ? () => _nudge(-10) : null),
                const MaterialPlayOrPauseButton(iconSize: FlickTokens.grid * 12),
                _SeekButton(_player, back: false,
                  onPressed: !widget.live || range != null ? () => _nudge(10) : null),
              ],
            ),
          ),
        ),
      ],
      bottomButtonBar: [
        if (_hasQueue) Builder(builder: (routeContext) => IconButton(
          tooltip: widget.live ? 'Live queue and servers' : 'Playback queue',
          onPressed: () => _showQueue(routeContext), icon: const Icon(Icons.playlist_play))),
        if (widget.live) const Text('Live', style: FlickText.button) else const MaterialPositionIndicator(),
        const Spacer(),
        if (!widget.live)
          StreamBuilder<double>(
            stream: _player.stream.rate,
            builder: (context, _) => TextButton(
              style: TextButton.styleFrom(
                foregroundColor: FlickTokens.textPrimary,
                minimumSize: const Size(48, 48),
              ),
              onPressed: () => _showSpeed(context),
              child: Tooltip(
                message: 'Playback speed',
                child: Text(speedLabel(_player.state.rate)),
              ),
            ),
          ),
        StreamBuilder<double>(
          stream: _player.stream.volume,
          builder: (context, _) {
            // The controls reuse this widget after hiding, so read live state.
            final muted = _player.state.volume == 0;
            return IconButton(
              tooltip: muted ? 'Volume (muted)' : 'Volume',
              onPressed: () => _showVolume(context),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
            );
          },
        ),
        IconButton(
          tooltip: 'Subtitles',
          onPressed: _openTracks,
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
        ListenableBuilder(
          listenable: _pip,
          builder: (_, _) => !_pip.supported
              ? const SizedBox.shrink()
              : StreamBuilder<bool>(
                  stream: _player.stream.playing,
                  initialData: _player.state.playing,
                  builder: (_, playing) => IconButton(
                    tooltip: 'Picture-in-picture',
                    onPressed: playing.data == true ? _enterPip : null,
                    icon: const Icon(Icons.picture_in_picture_alt),
                  ),
                ),
        ),
      ],
      seekBarColor: FlickTokens.textPrimary.withValues(alpha: 0.2),
      seekBarBufferColor: FlickTokens.textPrimary.withValues(alpha: 0.45),
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
        backgroundColor: FlickTokens.background,
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
                    subtitleViewConfiguration: subtitleView(_appearance),
                    // Android onStop pauses playback after PiP is dismissed.
                    pauseUponEnteringBackgroundMode: !_androidPip,
                    controls: _controls,
                    // media_kit's default shows the bars and unlocks rotation.
                    onExitFullscreen: _immersive,
                  ),
                ),
              ),
              if (!_pip.active && _error == null)
                Positioned.fill(
                  child: ExcludeFocus(
                    excluding: _panel,
                    child: ExcludeSemantics(
                      excluding: _panel,
                      child: BufferingPanel(
                        view: _bufferView,
                        waiting: _since != null,
                        title: _displayTitle,
                        logo: widget.playback?.logo,
                        poster: widget.playback?.poster,
                        onSwitch: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
              if (!_pip.active && next != null)
                Positioned.fill(
                  child: SafeArea(
                    child: Padding(
                      // Clears the 64 dp bottom bar whether it shows or not:
                      // media_kit keeps the controls' visibility private.
                      padding: const EdgeInsets.only(
                        right: FlickTokens.railGap,
                        bottom: _barHeight + FlickTokens.railGap,
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
              if (!_pip.active && _error != null)
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
                                  onPressed: widget.live && _hasQueue ? () => _showQueue(context) : () => Navigator.pop(context),
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
              if (!_pip.active && _panel)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: () => _togglePanel(false),
                  ),
                ),
              if (!_pip.active)
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

  Widget _buildTv() => Scaffold(
    backgroundColor: FlickTokens.background,
    body: Stack(
      children: [
        Video(
          key: _video,
          controller: _controller,
          subtitleViewConfiguration: subtitleView(_appearance),
          controls: NoVideoControls,
          onExitFullscreen: _immersive,
        ),
        Positioned.fill(
          child: ListenableBuilder(
            listenable: Listenable.merge([_tvRefresh, _controlNotice]),
            builder: (context, _) {
              final next = _next;
              final view = next == null
                  ? null
                  : _upNextView(next, _player.state.position);
              return TvPlayerControls(
                onQueue: _hasQueue ? () => _showQueue(context) : null,
                modal: _queueShowing || _controlNotice.value != null,
                onChooseSource: widget.live && _hasQueue ? () => _showQueue(context) : null,
                onSpeed: widget.live ? null : () => _showSpeed(context),
                live: widget.live,
                liveRange: _liveRange.value,
                title: _displayTitle,
                subtitle: widget.playback?.subtitle,
                position: _player.state.position,
                duration: _player.state.duration,
                buffer: _player.state.buffer,
                playing: _player.state.playing,
                muted: _player.state.volume == 0,
                onVolume: () => _showVolume(context),
                panel: _panel,
                tracks: _panel ? _tracksPanelTv() : const SizedBox(),
                buffering: _bufferView,
                waiting: _since != null,
                logo: widget.playback?.logo,
                poster: widget.playback?.poster,
                error: _error,
                retrying: _retrying,
                subtitlesOn: _activeSubtitle != 'Off',
                onToggle: () => _player.playOrPause().catchError(_showError),
                onSeek: _seekTo,
                onExit: () => Navigator.pop(context),
                onRetry: _retry,
                onTracks: () => _togglePanel(true),
                onCloseTracks: () {
                  if (_languages) {
                    _tvLanguages(false);
                  } else {
                    _togglePanel(false);
                  }
                },
                onNext: next == null || _resolving
                    ? null
                    : () => _commit(forced: true),
                upNextVisible: view?.visible ?? false,
                upNext: next == null
                    ? null
                    : UpNextCard(
                        view: view!,
                        episode: next.episode,
                        autoplay: settings.autoplayNext,
                        onNext: _commit,
                        onDismiss: () {
                          setState(() => _dismissed = true);
                          _upNext();
                        },
                        onAutoplay: _setAutoplay,
                      ),
              );
            },
          ),
        ),
        Positioned.fill(child: _controlFeedback()),
      ],
    ),
  );

  void _tvLanguages(bool open) {
    setState(() => _languages = open);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _panel) {
        (open ? _tvLanguageChoice : _tvLanguageFocus).requestFocus();
      }
    });
  }

  Widget _tracksPanelTv() {
    final captions = _captions;
    final languages = captions.map((c) => c.lang).toSet();
    final language = _language ?? languages.firstOrNull;
    final active = _selected ?? _player.state.track.subtitle;
    Widget row(
      String label,
      VoidCallback? onTap, {
      bool selected = false,
      String? detail,
      FocusNode? node,
    }) {
      final child = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: RevealArea(
          child: Semantics(
            selected: selected,
            child: FocusFrame.button(
              semanticLabel: [label, ?detail].join(', '),
              onActivate: onTap,
              focusNode: node,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (selected) ...[
                      const SlashMarker(),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FlickTv.body,
                          ),
                          if (detail != null)
                            Text(
                              detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: FlickTv.meta.copyWith(
                                color: FlickTokens.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return selected ? InitialFocus(child: child) : child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _languages ? 'Languages' : 'Subtitles & audio',
          style: FlickTv.railHeading,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(FlickTv.gridPad),
            children: [
              if (_languages) ...[
                for (final lang in languages)
                  row(
                    subtitleLanguageName(lang),
                    () {
                      _language = lang;
                      _tvLanguages(false);
                    },
                    selected: lang == language,
                    node: lang == language ? _tvLanguageChoice : null,
                  ),
                if (languages.isEmpty)
                  Text('No subtitle languages available', style: FlickTv.body),
              ] else ...[
                Text('Audio and subtitle choices are remembered for future videos.', style: FlickTv.meta),
                _subtitleAdjustments(),
                if (widget.downloadId != null) _offlineSubtitleControls(),
                row(
                  'Off',
                  _pending == null
                      ? () => _choose((
                          track: SubtitleTrack.no(),
                          url: null,
                          lang: language ?? 'und',
                          label: 'Off',
                          detail: '',
                        ))
                      : null,
                  selected: active.id == 'no' || active.id == 'auto',
                ),
                row(
                  'Language',
                  languages.isEmpty ? null : () => _tvLanguages(true),
                  node: _tvLanguageFocus,
                  detail: language == null
                      ? 'Choose language'
                      : subtitleLanguageName(language),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Skeleton(height: 48),
                  ),
                if (_catalogueError != null)
                  row(
                    'Retry subtitles',
                    _fetchSubtitles,
                    detail: _catalogueError,
                  ),
                if (_subtitleError != null)
                  row('Retry subtitle file', () {
                    if (_failed case final caption?) _choose(caption);
                  }, detail: _subtitleError),
                if (_notice != null)
                  row(
                    'Choose language',
                    languages.isEmpty ? null : () => _tvLanguages(true),
                    detail: _notice,
                  ),
                if (!_loading && _catalogueError == null && captions.isEmpty)
                  row('Retry subtitles', () {
                    _fetched = false;
                    _fetchSubtitles();
                  }, detail: 'No subtitles found for this episode'),
                for (final caption in captions.where((c) => c.lang == language))
                  row(
                    caption.label,
                    _pending == null ? () => _choose(caption) : null,
                    selected: active.id == caption.track.id,
                    detail: _pending == (caption.url ?? caption.track.id)
                        ? 'Opening subtitles…'
                        : caption.detail,
                  ),
                const SizedBox(height: 16),
                Text('Audio', style: FlickTv.card),
                for (final audio in _player.state.tracks.audio.where(
                  (a) => a.id != 'no' && a.id != 'auto',
                ))
                  row(
                    audio.title ??
                        subtitleLanguageName(audio.language ?? 'und'),
                    _audioPending ? null : () => _chooseAudio(audio),
                    selected: audio.id == _player.state.track.audio.id,
                  ),
                if (_next != null)
                  row(
                    'Autoplay next episode',
                    _resolving
                        ? null
                        : () => _setAutoplay(!settings.autoplayNext),
                    detail: settings.autoplayNext ? 'On' : 'Off',
                  ),
              ],
              row(_languages ? 'Back to subtitles' : 'Close', () {
                if (_languages) {
                  _tvLanguages(false);
                } else {
                  _togglePanel(false);
                }
              }),
            ],
          ),
        ),
      ],
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
    final groups = <String, List<Caption>>{};
    for (final caption in captions) {
      groups.putIfAbsent(caption.lang, () => []).add(caption);
    }
    final language = _language ?? (groups.isEmpty ? null : groups.keys.first);
    final files = groups[language] ?? const <Caption>[];
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
                                  const Padding(
                                    padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                                    child: Text('Audio and subtitle choices are remembered for future videos.', style: FlickText.metadata),
                                  ),
                                  _subtitleAdjustments(),
                                  if (widget.downloadId != null) _offlineSubtitleControls(),
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
                                        onTap: _audioPending ? null : () => _chooseAudio(track),
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

/// A ±10 s bar button. media_kit fades its middle bar out while buffering, and
/// mpv buffers briefly after every seek, so the button stays tappable then: a
/// second press a second after the first must still count (found on the
/// phone). It leaves TalkBack alone while it can't be seen. It listens itself:
/// media_kit never rebuilds its bars.
class _SeekButton extends StatelessWidget {
  const _SeekButton(this.player, {required this.back, required this.onPressed});

  final Player player;
  final bool back;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: player.stream.buffering,
    initialData: player.state.buffering,
    builder: (_, buffering) {
      return ExcludeSemantics(
        excluding: buffering.data ?? false,
        child: IconButton(
          tooltip: back ? 'Back 10 seconds' : 'Forward 10 seconds',
          onPressed: onPressed,
          iconSize: FlickTokens.grid * 9,
          color: FlickTokens.textPrimary,
          constraints: const BoxConstraints(
            minWidth: FlickTokens.minTouchTarget,
            minHeight: FlickTokens.minTouchTarget,
          ),
          icon: Icon(back ? Icons.replay_10 : Icons.forward_10),
        ),
      );
    },
  );
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
          style: const TextStyle(color: FlickTokens.textSecondary, fontSize: 12),
          children: [
            const TextSpan(text: 'Buffered '),
            TextSpan(
              text:
                  '${s.inMinutes}:${(s.inSeconds % 60).toString().padLeft(2, '0')}',
              style: monoStyle.copyWith(color: FlickTokens.textSecondary, fontSize: 12),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [FlickTokens.background.withValues(alpha: 0.7), FlickTokens.background.withValues(alpha: 0)],
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 4),
            SizedBox.square(
              dimension: 48,
              child: BackButton(
                color: FlickTokens.textPrimary,
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
                    style: t.titleSmall?.copyWith(color: FlickTokens.textPrimary),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(color: FlickTokens.textSecondary),
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
