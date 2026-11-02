import 'package:flutter/material.dart';

import '../history.dart';
import '../kit/focus.dart';
import '../theme.dart';

/// Local unfinished-video checkpoints; removing one also removes its automatic resume position.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen(this.history, {super.key});
  final ViewingHistory history;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _back = FocusNode(debugLabel: 'History Back');
  bool _confirm = false, _busy = false;
  Future<void> Function()? _retry;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_busy) return;
    setState(() { _busy = true; _confirm = false; _retry = null; });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _retry = action);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (context.tv) tvReveal(_back);
      }
    }
  }

  Widget _action(String label, VoidCallback onTap, {FocusNode? node, bool autofocus = false}) {
    if (!context.tv) return TextButton(onPressed: _busy ? null : onTap, child: Text(label));
    return FocusFrame.button(
      focusNode: node, autofocus: autofocus, semanticLabel: label,
      onActivate: _busy ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FlickTokens.minTouchTarget),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(label, style: FlickTv.body)),
      ),
    );
  }

  String _time(Duration value) {
    final minutes = value.inMinutes;
    return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _entry(WatchProgress progress) => RevealArea(key: ValueKey(progress.key), child: Padding(
    padding: const EdgeInsets.symmetric(vertical: FlickTokens.railGap),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(progress.title, style: context.tv ? FlickTv.railHeading : FlickText.railHeading),
      if (progress.subtitle != null) Text(progress.subtitle!, style: context.tv ? FlickTv.body : FlickText.body),
      Text('${_time(progress.position)}${progress.duration > Duration.zero ? ' / ${_time(progress.duration)}' : ''}',
        style: context.tv ? FlickTv.meta : FlickText.metadata),
      _action('Remove from history', () => _change(() => widget.history.remove(progress.type, progress.videoId, scope: progress.scope))),
    ]),
  ));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(context.tv ? FlickTv.insetH : FlickTokens.pageGutter,
            context.tv ? FlickTv.insetV : 0, context.tv ? FlickTv.insetH : FlickTokens.pageGutter, 0),
          child: Align(alignment: Alignment.centerLeft, child: _action('Back', () => Navigator.pop(context),
            node: _back, autofocus: context.tv)),
        ),
        Expanded(child: ListenableBuilder(listenable: widget.history, builder: (context, _) {
        final entries = widget.history.entries;
        return ListView(
          padding: EdgeInsets.all(context.tv ? FlickTv.insetH : FlickTokens.pageGutter),
          children: [
            Text('Viewing history', style: context.tv ? FlickTv.page : FlickText.pageTitle),
            const SizedBox(height: FlickTokens.railGap),
            Text('Unfinished videos saved on this device. Removing a video clears its resume position.',
              style: context.tv ? FlickTv.body : FlickText.body),
            if (_retry != null) ...[
              const SizedBox(height: FlickTokens.railGap),
              Text('Could not save the history change. Retry to keep it after restart.',
                style: context.tv ? FlickTv.body : FlickText.body),
              Align(alignment: Alignment.centerLeft, child: _action('Retry', () => _change(_retry!))),
            ],
            if (entries.isNotEmpty) ...[
              const SizedBox(height: FlickTokens.railGap),
              if (_confirm) ...[
                Text('Clear all viewing history? All saved resume positions will be removed.',
                  style: context.tv ? FlickTv.body : FlickText.body),
                Wrap(spacing: FlickTokens.railGap, children: [
                  _action('Cancel', () => setState(() => _confirm = false)),
                  _action('Clear history', () => _change(widget.history.clear)),
                ]),
              ] else Align(alignment: Alignment.centerLeft,
                child: _action('Clear all', () => setState(() => _confirm = true))),
              for (final entry in entries) _entry(entry),
            ] else ...[
              const SizedBox(height: FlickTokens.sectionGap),
              Text('No unfinished videos', style: context.tv ? FlickTv.railHeading : FlickText.railHeading),
            ],
          ],
        );
      })),
      ]),
    )),
  );
}
