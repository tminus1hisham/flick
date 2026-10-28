import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin.dart';
import '../stall.dart';
import '../state.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.item, this.source, this.report = true, super.key});
  final Item item;

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
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
    final bar = <Widget>[
      const BackButton(color: Colors.white),
      Expanded(
        child: Text(widget.item.title,
            style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis),
      ),
      _BufferAhead(_player),
      if (widget.source == null)
        PopupMenuButton<Quality>(
          icon: const Icon(Icons.high_quality, color: Colors.white),
          initialValue: _quality,
          onSelected: _switch,
          itemBuilder: (_) => [
            for (final q in Quality.values) PopupMenuItem(value: q, child: Text(q.label)),
          ],
        ),
    ];
    final theme = MaterialVideoControlsThemeData(
      topButtonBar: bar,
      seekBarBufferColor: Colors.white54,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: theme,
        fullscreen: theme,
        child: Video(controller: _controller),
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
          return Text(
            'Buffered ${s.inMinutes}:${(s.inSeconds % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          );
        },
      );
}
