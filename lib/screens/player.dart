import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../jellyfin.dart';
import '../stall.dart';
import '../state.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({required this.item, this.localPath, super.key});
  final Item item;
  final String? localPath;

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

  JellyfinClient? get _client => session.online ? session.client : null;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _subs
      ..add(_player.stream.position.listen((p) {
        if (p > const Duration(seconds: 1)) _started = true;
      }))
      ..add(_player.stream.buffering.listen(_onBuffering));
    _init();
  }

  Future<void> _init() async {
    final mpv = _player.platform as NativePlayer;
    // Buffer hard up front and after a stall instead of stuttering.
    for (final (k, v) in [
      ('cache', 'yes'),
      ('demuxer-max-back-bytes', '${100 * 1024 * 1024}'),
      ('demuxer-readahead-secs', '300'),
      ('cache-pause-initial', 'yes'),
      ('cache-pause-wait', '8'),
    ]) {
      await mpv.setProperty(k, v);
    }
    await _open(widget.item.resumePosition);
    _report((c) => c.reportStart(widget.item.id, _player.state.position));
    _progress = Timer.periodic(const Duration(seconds: 10), (_) => _report((c) =>
        c.reportProgress(widget.item.id, _player.state.position, paused: !_player.state.playing)));
  }

  Future<void> _open(Duration start) => _player.open(Media(
        widget.localPath ?? session.client!.playUrl(widget.item, _quality),
        start: start,
      ));

  void _report(Future<void> Function(JellyfinClient) call) {
    final c = _client;
    if (c != null) call(c).catchError((_) {}); // progress is best-effort
  }

  void _onBuffering(bool buffering) {
    if (!buffering || !_started || _prompted) return;
    if (widget.localPath != null || _quality != Quality.original) return;
    if (!_stalls.record(DateTime.now())) return;
    _prompted = true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 15),
      content: const Text('Playback keeps stalling on this connection'),
      action: SnackBarAction(label: 'Use 1.5 Mbps', onPressed: () => _switch(Quality.mbps1_5)),
    ));
  }

  Future<void> _switch(Quality q) async {
    if (q == _quality) return;
    final pos = _player.state.position;
    setState(() => _quality = q);
    _stalls.reset();
    await _open(pos);
  }

  @override
  void dispose() {
    final pos = _player.state.position;
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
      if (widget.localPath == null)
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
