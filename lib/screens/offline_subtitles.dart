import 'package:flutter/material.dart';

import '../kit/focus.dart';
import '../theme.dart';

class OfflineSubtitleControls extends StatefulWidget {
  const OfflineSubtitleControls({required this.saved, required this.save, required this.remove,
    required this.findOnline, super.key});
  final bool saved;
  final Future<void> Function()? save, remove;
  final Future<void> Function() findOnline;
  @override
  State<OfflineSubtitleControls> createState() => _OfflineSubtitleControlsState();
}

class _OfflineSubtitleControlsState extends State<OfflineSubtitleControls> {
  bool _busy = false;
  String? _error;
  Future<void> Function()? _retry;
  final _findFocus = FocusNode(debugLabel: 'Offline subtitle search');

  @override
  void dispose() { _findFocus.dispose(); super.dispose(); }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; _retry = null; });
    try { await action(); }
    catch (e) {
      if (mounted) { setState(() {
        _error = e is FormatException ? 'Use a non-empty text subtitle no larger than 2 MB.'
          : 'Could not update the offline subtitle. Check storage and retry.';
        _retry = action;
      }); }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final focus = FocusManager.instance.primaryFocus;
          if (focus == null || focus.context == null || focus is FocusScopeNode) tvReveal(_findFocus);
        });
      }
    }
  }

  Widget _button(String label, Future<void> Function()? action, {FocusNode? node, Key? key}) {
    final onTap = action == null || _busy ? null : () => _run(action);
    final text = Text(label, style: context.tv ? FlickTv.meta : FlickText.button);
    final child = context.tv ? ExcludeFocus(excluding: onTap == null, child: RevealArea(child: FocusFrame.button(
      semanticLabel: label, onActivate: onTap, focusNode: node,
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(padding: const EdgeInsets.all(12), child: text))))) : TextButton(
      onPressed: onTap, focusNode: node, style: TextButton.styleFrom(minimumSize: const Size(48, 48)), child: text);
    return Semantics(key: key, button: true, enabled: onTap != null, child: child);
  }

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(12), child: Column(
    crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(liveRegion: true, child: Text(widget.saved ? 'Subtitle saved for offline playback.'
        : 'Select an external subtitle, then save it for this download. Embedded tracks stay in the video.',
        style: context.tv ? FlickTv.meta : FlickText.metadata)),
      Wrap(spacing: 8, children: [
        _button(widget.saved ? 'Replace saved subtitle' : 'Save subtitle offline', widget.save),
        if (widget.saved) _button('Remove saved subtitle', widget.remove),
        _button('Find online subtitles', widget.findOnline, node: _findFocus, key: const ValueKey('find-subtitles')),
      ]),
      if (_busy) Text('Updating subtitles…', style: context.tv ? FlickTv.meta : FlickText.metadata),
      if (_error != null) ...[
        Semantics(liveRegion: true, child: Text(_error!, style: context.tv ? FlickTv.meta : FlickText.metadata)),
        _button('Retry offline subtitle', _retry),
      ],
    ],
  ));
}
