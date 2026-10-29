import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin.dart';
import '../addons.dart' show Subtitle;
import '../stall.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.item, this.source, this.report = true,
    this.headers = const {}, this.subtitles = const [], super.key});
  final Item item;
  final Map<String, String> headers;
  final List<Subtitle> subtitles;

  /// Plays this file/URL instead of streaming from Jellyfin.
  final String? source;

  /// Report playback progress to Jellyfin for [item].
  final bool report;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _player = Player(configuration: const PlayerConfiguration(bufferSize: 400 * 1024 * 1024));
  late final _controller = VideoController(_player);
  final _stalls = StallDetector();
  final _subs = <StreamSubscription>[];
  Quality _quality = Quality.original;
  bool _started = false, _prompted = false;
  Timer? _progress;
  String? _error;
  bool _retrying = false;
  ScaffoldMessengerState? _messenger;
  // open() resets state.position to 0 until mpv reports time-pos; report this instead.
  late Duration _pos = widget.item.resumePosition;

  JellyfinClient? get _client => widget.report && session.online ? session.client : null;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _subs
      ..add(_player.stream.position.listen((p) {
        if (p > Duration.zero) _pos = p;
      }))
      ..add(_player.stream.buffering.listen(_onBuffering))
      ..add(_player.stream.error.listen(_showError));
    _init().catchError(_showError);
  }

  void _showError(Object e) {
    if (widget.source != null) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      setState(() => _error = null);
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
    // Read-ahead is bounded by bufferSize (demuxer-max-bytes) only.
    for (final (k, v) in [
      ('demuxer-max-back-bytes', '${100 * 1024 * 1024}'),
      ('cache-pause-initial', 'yes'),
      ('cache-pause-wait', '8'),
      // Torrent sources: the server holds a request open until its piece downloads, so outwait
      // media_kit's 5 s network-timeout, and reconnect at the current offset if it drops an idle one.
      if (!widget.report) ('network-timeout', '60'),
      if (!widget.report)
        ('stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5'),
    ]) {
      if (!mounted) return;
      await mpv.setProperty(k, v);
    }
    if (!mounted) return;
    await _open(_pos);
    if (!mounted) return;
    _report((c) => c.reportStart(widget.item.id, _pos));
    _progress = Timer.periodic(const Duration(seconds: 10), (_) => _report((c) =>
        c.reportProgress(widget.item.id, _pos, paused: !_player.state.playing)));
  }

  Future<void> _open(Duration start) => _player.open(Media(
        widget.source ?? session.client!.playUrl(widget.item, _quality),
        start: start,
        httpHeaders: widget.headers,
      ));

  void _report(Future<void> Function(JellyfinClient) call) {
    final c = _client;
    if (c != null) call(c).catchError((_) {}); // progress is best-effort
  }

  void _onBuffering(bool buffering) {
    if (!buffering) {
      // The first buffer-complete after real playback position ends the initial fill.
      if (_player.state.position > Duration.zero) _started = true;
      return;
    }
    // ponytail: out-of-cache seeks also count as stalls.
    if (!_started || _prompted) return;
    if (widget.source != null || _quality != Quality.original) return;
    if (!_stalls.record(DateTime.now())) return;
    _prompted = true;
    _messenger = ScaffoldMessenger.of(context)..showSnackBar(SnackBar(
      duration: const Duration(seconds: 15),
      content: const Text('Playback keeps stalling on this connection'),
      action: SnackBarAction(label: 'Use 1.5 Mbps', onPressed: () => _switch(Quality.mbps1_5)),
    ));
  }

  Future<void> _switch(Quality q) async {
    if (q == _quality || !mounted) return;
    setState(() => _quality = q);
    _stalls.reset();
    await _open(_pos);
  }

  @override
  void dispose() {
    _messenger?.hideCurrentSnackBar();
    final pos = _pos;
    _report((c) => c.reportStopped(widget.item.id, pos));
    _progress?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final bar = <Widget>[
      _TopBar(
        title: headline(item),
        subtitle: episodeLine(item),
        buffer: _BufferAhead(_player),
        quality: widget.source == null
            ? PopupMenuButton<Quality>(
                tooltip: 'Playback quality',
                initialValue: _quality,
                onSelected: _switch,
                itemBuilder: (_) => [
                  for (final q in Quality.values) PopupMenuItem(value: q, child: Text(q.label)),
                ],
                child: SizedBox(
                  height: 48,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.high_quality, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(_quality.label,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white)),
                    const SizedBox(width: 8),
                  ]),
                ),
              )
            : null,
      ),
    ];
    final theme = MaterialVideoControlsThemeData(
      topButtonBar: bar,
      topButtonBarMargin: EdgeInsets.zero,
      buttonBarHeight: 64,
      seekBarColor: Colors.white.withValues(alpha: 0.2),
      seekBarBufferColor: Colors.white.withValues(alpha: 0.45),
      seekBarPositionColor: FlickTokens.accent,
      seekBarThumbColor: FlickTokens.accent,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: theme,
        fullscreen: theme,
        child: Stack(children: [
          Video(controller: _controller),
          if (_error != null)
            Positioned.fill(
              child: ColoredBox(
                color: FlickTokens.background,
                child: Center(child: SingleChildScrollView(
                  padding: const EdgeInsets.all(FlickTokens.pageGutter),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.report_outlined, color: context.flick.danger),
                    const SizedBox(height: 12),
                    const Text("Couldn't play this video"),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: _retrying ? null : _retry, child: const Text('Retry')),
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Choose another source')),
                    ]),
                  ]),
                )),
              ),
            ),
        ]),
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
            TextSpan(style: const TextStyle(color: Colors.white70, fontSize: 12), children: [
              const TextSpan(text: 'Buffered '),
              TextSpan(
                text: '${s.inMinutes}:${(s.inSeconds % 60).toString().padLeft(2, '0')}',
                style: monoStyle.copyWith(color: Colors.white70, fontSize: 12),
              ),
            ]),
          );
        },
      );
}

/// Back target, title block (with buffer readout) and optional quality menu over a soft scrim.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.subtitle, required this.buffer, this.quality});
  final String title;
  final String? subtitle;
  final Widget buffer;
  final Widget? quality;

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
        child: Row(children: [
          const SizedBox(width: 4),
          SizedBox.square(
            dimension: 48,
            child: BackButton(
                color: Colors.white, style: IconButton.styleFrom(minimumSize: const Size.square(48))),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: subtitle == null ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(color: Colors.white)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(color: Colors.white70)),
                buffer,
              ],
            ),
          ),
          ?quality,
          const SizedBox(width: 8),
        ]),
      ),
    );
  }
}
