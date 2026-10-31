import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../kit/focus.dart';
import '../player_keys.dart';
import '../stall.dart';
import '../theme.dart';
import 'buffering.dart';

/// Remote controls, independent of libmpv so the complete key/focus contract is widget-testable.
class TvPlayerControls extends StatefulWidget {
  const TvPlayerControls({required this.title, this.subtitle, required this.position, required this.duration,
    required this.buffer, required this.playing, required this.panel, required this.tracks,
    required this.buffering, required this.onToggle, required this.onSeek, required this.onExit,
    required this.onTracks, required this.onCloseTracks, required this.onRetry,
    this.logo, this.poster, this.waiting = false, this.error, this.retrying = false, this.subtitlesOn = false, this.onNext, this.upNext, this.upNextVisible = false, super.key});
  final String title;
  final String? subtitle, error, logo, poster;
  final bool waiting;
  final Duration position, duration, buffer;
  final bool playing, panel, retrying, upNextVisible, subtitlesOn;
  final Widget tracks;
  final Widget? upNext;
  final BufferView buffering;
  final VoidCallback onToggle, onExit, onTracks, onCloseTracks, onRetry;
  final VoidCallback? onNext;
  final ValueChanged<Duration> onSeek;
  @override
  State<TvPlayerControls> createState() => _TvPlayerControlsState();
}

class _TvPlayerControlsState extends State<TvPlayerControls> {
  final _keys = FocusNode(debugLabel: 'Player keys');
  final _play = FocusNode(debugLabel: 'Play pause');
  final _tracks = FocusNode(debugLabel: 'Subtitles');
  final _next = FocusNode(debugLabel: 'Next episode');
  final _retry = FocusNode(debugLabel: 'Retry playback');
  final _waiting = FocusScopeNode(debugLabel: 'Buffering recovery', directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope);
  final _card = FocusScopeNode(debugLabel: 'Up Next', directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope);
  final _panel = FocusScopeNode(debugLabel: 'Tracks', directionalTraversalEdgeBehavior: TraversalEdgeBehavior.stop);
  Timer? _timer, _hintTimer;
  bool _bar = false;
  Duration? _hint, _heldAt;
  LogicalKeyboardKey? _heldKey;

  void _arm() {
    _timer?.cancel();
    if (!_bar || !widget.playing || widget.panel || _card.hasFocus || _waiting.hasFocus || widget.error != null) return;
    _timer = Timer(const Duration(seconds: 4), _hide);
  }

  void _show() {
    setState(() => _bar = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && !widget.panel) _play.requestFocus(); });
    _arm();
  }

  void _hide() {
    _timer?.cancel();
    if (!mounted || widget.panel || widget.error != null) return;
    setState(() => _bar = false);
    _keys.requestFocus();
  }

  void _panelFocus() {
    if (_panel.hasPrimaryFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.panel && _panel.hasPrimaryFocus) enterScope(_panel);
      });
    }
  }

  void _cardFocus() => _arm();

  void _seek(bool forward, KeyEvent event) {
    if (event is! KeyRepeatEvent || _heldKey != event.logicalKey) {
      _heldAt = event.timeStamp;
      _heldKey = event.logicalKey;
    }
    final target = tvSeek(_hint ?? widget.position, widget.duration, forward: forward,
      held: event.timeStamp - (_heldAt ?? event.timeStamp));
    if (target == null) { _show(); return; }
    setState(() => _hint = target);
    widget.onSeek(target);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 1), () { if (mounted) setState(() => _hint = null); });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == _heldKey) { _heldAt = null; _heldKey = null; }
      return KeyEventResult.ignored;
    }
    // Android also sends popRoute for Back; PopScope owns that press once.
    if (event.logicalKey == LogicalKeyboardKey.goBack && defaultTargetPlatform == TargetPlatform.android) {
      return KeyEventResult.ignored;
    }
    _arm();
    final key = event.logicalKey;
    if (widget.error != null && !widget.panel) {
      if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
        widget.onExit(); return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_waiting.hasFocus && key == LogicalKeyboardKey.arrowDown) {
      _show(); return KeyEventResult.handled;
    }
    if (_bar && !widget.panel && key == LogicalKeyboardKey.arrowUp && widget.upNextVisible &&
        (_tracks.hasFocus || _next.hasFocus)) {
      enterScope(_card);
      return KeyEventResult.handled;
    }
    // Down from the card returns to the bar; its own controls still receive Left/Right and Select.
    if (_card.hasFocus && key == LogicalKeyboardKey.arrowDown) {
      _play.requestFocus();
      return KeyEventResult.handled;
    }
    final command = tvPlayerKey(key, bar: _bar || _card.hasFocus || _waiting.hasFocus, panel: widget.panel, repeat: event is KeyRepeatEvent);
    switch (command) {
      case TvPlayerCommand.toggle:
        widget.onToggle();
        if (!widget.panel && !_bar) _show();
      case TvPlayerCommand.play:
        if (!widget.playing) widget.onToggle();
      case TvPlayerCommand.pause:
        if (widget.playing) widget.onToggle();
      case TvPlayerCommand.backward: _seek(false, event);
      case TvPlayerCommand.forward: _seek(true, event);
      case TvPlayerCommand.show: _show();
      case TvPlayerCommand.hide: _hide();
      case TvPlayerCommand.closeTracks: widget.onCloseTracks();
      case TvPlayerCommand.exit: widget.onExit();
      case TvPlayerCommand.none: return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    _panel.addListener(_panelFocus);
    _card.addListener(_cardFocus);
    _waiting.addListener(_cardFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.error != null) { _retry.requestFocus(); }
      else if (widget.panel) { enterScope(_panel); }
      else if (widget.buffering.offerSwitch) { enterScope(_waiting); }
    });
  }

  @override
  void didUpdateWidget(TvPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _arm();
    if (oldWidget.panel != widget.panel) {
      _timer?.cancel();
      if (widget.panel) _bar = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.panel) { enterScope(_panel); }
        else if (widget.error != null) { _retry.requestFocus(); }
        else { _tracks.requestFocus(); _arm(); }
      });
    }
    if (oldWidget.error == null && widget.error != null && !widget.panel) {
      _timer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _retry.requestFocus(); });
    } else if (oldWidget.error != null && widget.error == null && !widget.panel) {
      _bar = false;
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _keys.requestFocus(); });
    }
    if (oldWidget.buffering.offerSwitch && !widget.buffering.offerSwitch && _waiting.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) { (_bar ? _play : _keys).requestFocus(); }
      });
    }
    if (oldWidget.upNextVisible && !widget.upNextVisible && _card.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _play.requestFocus(); });
    }
  }

  @override
  void dispose() {
    _timer?.cancel(); _hintTimer?.cancel();
    _panel.removeListener(_panelFocus); _card.removeListener(_cardFocus); _waiting.removeListener(_cardFocus);
    for (final node in [_keys, _play, _tracks, _next, _retry, _card, _panel, _waiting]) { node.dispose(); }
    super.dispose();
  }

  Widget _button(IconData icon, String label, VoidCallback? action, {FocusNode? node, bool disc = false, bool selected = false}) =>
    FocusFrame.button(focusNode: node, semanticLabel: label, onActivate: action,
      radius: disc ? FlickTokens.minTouchTarget : FlickTokens.controlRadius,
      child: Container(constraints: const BoxConstraints(minHeight: FlickTokens.minTouchTarget),
        padding: EdgeInsets.symmetric(horizontal: disc ? 12 : 16, vertical: 12),
        decoration: disc ? const BoxDecoration(color: FlickTokens.surface2, shape: BoxShape.circle) : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [if (selected) ...[const SlashMarker(), const SizedBox(width: 8)], Icon(icon, size: 24),
          if (!disc) ...[const SizedBox(width: 8), Text(label, style: FlickTv.body)],
        ])),
    );

  Widget _barView() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Semantics(label: '${playerTime(widget.position)} of ${playerTime(widget.duration)}', child: SizedBox(height: 4,
      child: LayoutBuilder(builder: (context, box) => Stack(children: [
        const Positioned.fill(child: ColoredBox(color: FlickTokens.outline)),
        Align(alignment: Alignment.centerLeft, child: SizedBox(width: box.maxWidth * _fraction(widget.buffer), height: 4,
          child: const ColoredBox(color: FlickTokens.textSecondary))),
        Align(alignment: Alignment.centerLeft, child: SizedBox(width: box.maxWidth * _fraction(widget.position), height: 4,
          child: const ColoredBox(color: FlickTokens.activeMarker))),
      ])),
    )),
    const SizedBox(height: 20),
    Row(children: [
      _button(widget.playing ? Icons.pause : Icons.play_arrow_rounded, widget.playing ? 'Pause' : 'Play',
        () { widget.onToggle(); _arm(); }, node: _play, disc: true),
      const SizedBox(width: 16),
      Expanded(child: Text('${playerTime(widget.position)} / ${playerTime(widget.duration)}',
        style: monoStyle.copyWith(fontSize: 16, height: 22 / 16))),
      _button(Icons.closed_caption_outlined, 'Subtitles', widget.onTracks, node: _tracks, selected: widget.subtitlesOn),
      if (widget.onNext != null) ...[
        const SizedBox(width: 16), _button(Icons.skip_next, 'Next episode', widget.onNext, node: _next),
      ],
    ]),
  ]);

  double _fraction(Duration duration) => widget.duration > Duration.zero
      ? (duration.inMilliseconds / widget.duration.inMilliseconds).clamp(0.0, 1.0) : 0;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !widget.panel && (widget.error != null || !_bar),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) { widget.panel ? widget.onCloseTracks() : _hide(); }
    },
    child: Focus(focusNode: _keys, autofocus: true, skipTraversal: true, onKeyEvent: _key,
      child: FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
        child: Stack(children: [
          if (_bar && widget.error == null) Positioned.fill(child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(gradient: context.flick.scrimTop)))),
          // The scrims use the established transparent middle so the video stays visible.
          if (_bar && widget.error == null) Positioned.fill(child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(gradient: context.flick.scrimBottom)))),
          if (widget.error == null) ExcludeFocus(excluding: widget.panel, child: ExcludeSemantics(excluding: widget.panel,
            child: Stack(children: [
              if (_bar) Positioned(left: FlickTv.insetH, right: FlickTv.insetH, top: FlickTv.insetV,
                child: IgnorePointer(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: FlickTv.page),
                  if (widget.subtitle != null) Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: FlickTv.body),
                ]))),
              Positioned.fill(child: FocusScope(node: _waiting, canRequestFocus: widget.buffering.offerSwitch,
                child: BufferingPanel(view: widget.buffering, title: widget.title, logo: widget.logo, poster: widget.poster,
                  waiting: widget.waiting, onSwitch: widget.onExit))),
              if (widget.upNext != null) Positioned(right: FlickTv.insetH + FlickTv.gridPad,
                bottom: FlickTv.insetV + 112,
                child: FocusScope(node: _card, child: widget.upNext!)),
              if (_bar) Positioned(left: FlickTv.insetH + FlickTv.gridPad, right: FlickTv.insetH + FlickTv.gridPad,
                bottom: FlickTv.insetV + FlickTv.gridPad, child: _barView()),
              if (_hint != null) Positioned(left: FlickTv.insetH, right: FlickTv.insetH, bottom: FlickTv.insetV + 40,
                child: Center(child: Semantics(liveRegion: true, child: Text('Seeking ${playerTime(_hint!)}',
                  style: monoStyle.copyWith(fontSize: 18, backgroundColor: FlickTokens.surface1))))),
            ]))),
          if (widget.error != null) Positioned.fill(child: ExcludeFocus(excluding: widget.panel,
            child: ColoredBox(color: FlickTokens.background, child: Center(child: Padding(
              padding: const EdgeInsets.all(FlickTv.insetH),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.report_outlined, color: context.flick.danger),
                const SizedBox(height: 16), Text("Couldn't play this video", style: FlickTv.railHeading),
                const SizedBox(height: 8), Text("The source didn't respond or the file can't be played.", style: FlickTv.body),
                const SizedBox(height: 24), Wrap(spacing: 16, runSpacing: 16, children: [
                  _button(Icons.refresh, widget.retrying ? 'Retrying…' : 'Retry', widget.retrying ? null : widget.onRetry, node: _retry),
                  _button(Icons.arrow_back, 'Choose another source', widget.onExit),
                ]),
              ]),
            ))))),
          if (widget.panel) Positioned(top: 0, right: 0, bottom: 0, width: FlickTv.tracksPanel,
            child: Material(color: FlickTokens.surface1, child: Padding(
              padding: const EdgeInsets.fromLTRB(16, FlickTv.insetV + FlickTv.gridPad,
                FlickTv.insetH + FlickTv.gridPad, FlickTv.insetV + FlickTv.gridPad),
              child: FocusScope(node: _panel, child: widget.tracks),
            ))),
        ]),
      ),
    ),
  );
}
