import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../kit/focus.dart';
import '../subtitles.dart';
import '../theme.dart';

SubtitleViewConfiguration subtitleView(SubtitleAppearance appearance) => SubtitleViewConfiguration(
  style: TextStyle(height: 1.4, fontSize: 32 * appearance.size / 100, letterSpacing: 0, wordSpacing: 0,
    color: FlickTokens.textPrimary,
    backgroundColor: appearance.background ? FlickTokens.background.withValues(alpha: 0.85) : null,
    shadows: appearance.background ? null : const [
      Shadow(color: FlickTokens.background, offset: Offset(-1, -1), blurRadius: 2),
      Shadow(color: FlickTokens.background, offset: Offset(1, -1), blurRadius: 2),
      Shadow(color: FlickTokens.background, offset: Offset(-1, 1), blurRadius: 2),
      Shadow(color: FlickTokens.background, offset: Offset(1, 1), blurRadius: 2),
    ]),
);

class SubtitleAdjustments extends StatefulWidget {
  const SubtitleAdjustments({required this.appearance, required this.delay, required this.timingEnabled,
    required this.onDelay, required this.onAppearance, super.key});
  final SubtitleAppearance appearance;
  final int delay;
  final bool timingEnabled;
  final Future<void> Function(int) onDelay;
  final Future<void> Function(SubtitleAppearance) onAppearance;
  @override
  State<SubtitleAdjustments> createState() => _SubtitleAdjustmentsState();
}

class _SubtitleAdjustmentsState extends State<SubtitleAdjustments> {
  bool _busy = false, _expanded = false;
  String? _error;
  Future<void> Function()? _retry;

  Future<void> _run(Future<void> Function() action, String error) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _retry = null; });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() { _error = error; _retry = action; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _delay(int value) => _run(() => widget.onDelay(value), 'Could not adjust subtitle timing.');
  void _appearance(SubtitleAppearance value) => _run(() => widget.onAppearance(value),
    'Appearance is applied, but could not be saved for future videos.');

  Widget _button(String label, VoidCallback? action, {bool? selected}) {
    final enabled = _busy ? null : action;
    final text = Text(label, style: context.tv ? FlickTv.meta : FlickText.button);
    final child = context.tv ? ExcludeFocus(excluding: enabled == null, child: RevealArea(
      child: FocusFrame.button(semanticLabel: label, onActivate: enabled,
        child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(padding: const EdgeInsets.all(12), child: text))))) : TextButton(
        onPressed: enabled, style: TextButton.styleFrom(minimumSize: const Size(48, 48)), child: text);
    return Semantics(button: true, enabled: enabled != null, selected: selected, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final appearance = widget.appearance;
    final meta = context.tv ? FlickTv.meta : FlickText.metadata;
    final delay = widget.delay;
    final time = delay == 0 ? 'In sync' : '${delay > 0 ? '+' : '−'}${(delay.abs() / 1000).toStringAsFixed(2)} s · ${delay > 0 ? 'later' : 'earlier'}';
    return Padding(padding: const EdgeInsets.all(12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(expanded: _expanded, child: _button('Timing & appearance',
          () => setState(() => _expanded = !_expanded))),
        if (_expanded) ...[
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text('Timing · $time', style: meta)),
        Wrap(spacing: 8, children: [
          _button('Earlier −0.25 s', widget.timingEnabled && delay > -30000 ? () => _delay(delay - 250) : null),
          _button('Later +0.25 s', widget.timingEnabled && delay < 30000 ? () => _delay(delay + 250) : null),
          _button('Reset timing', widget.timingEnabled ? () => _delay(0) : null),
        ]),
        Text(widget.timingEnabled ? 'Timing is kept for this subtitle until you leave this video.'
          : 'Select a subtitle to adjust its timing.', style: meta),
        const SizedBox(height: 12),
        Semantics(liveRegion: true, child: Text('Text size · ${appearance.size}%', style: meta)),
        Wrap(spacing: 8, children: [
          _button('Smaller', appearance.size > 75 ? () => _appearance((size: appearance.size - 25, background: appearance.background)) : null),
          _button('Larger', appearance.size < 200 ? () => _appearance((size: appearance.size + 25, background: appearance.background)) : null),
          _button('Reset size', () => _appearance((size: 100, background: appearance.background))),
        ]),
        Text('Contrast', style: meta),
        Wrap(spacing: 8, children: [
          _button('Dark background', () => _appearance((size: appearance.size, background: true)), selected: appearance.background),
          _button('Dark outline', () => _appearance((size: appearance.size, background: false)), selected: !appearance.background),
        ]),
        const SizedBox(height: 8),
        Text('Captions look like this.', style: subtitleView(appearance).style.copyWith(fontSize: 18 * appearance.size / 100)),
        const SizedBox(height: 12),
        Text('Appearance is remembered. Text captions only: ASS styling is flattened; image subtitles are not supported.', style: meta),
        if (_error != null) ...[
          Semantics(liveRegion: true, child: Text(_error!, style: meta)),
          _button('Retry adjustment', () => _run(_retry!, _error!)),
        ],
        ],
      ],
    ));
  }
}
