import 'dart:async';

import 'package:flutter/material.dart';

import '../kit/focus.dart';
import '../kit/tv_surface.dart';
import '../state.dart';
import '../theme.dart';

/// Shared by empty, native and HTTP download lists.
class DownloadControls extends StatefulWidget {
  const DownloadControls({super.key});

  @override
  State<DownloadControls> createState() => _DownloadControlsState();
}

class _DownloadControlsState extends State<DownloadControls> with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(downloads.refreshEnvironment());
    });
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => downloads.refreshEnvironment());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(downloads.refreshEnvironment());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await downloads.setWifiOnly(!downloads.wifiOnly);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not change the network choice. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _size(int? bytes) => bytes == null ? 'Unavailable' : '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: downloads, builder: (context, _) {
    final text = context.tv ? FlickTv.meta : FlickText.metadata;
    final label = 'Wi-Fi only: ${downloads.wifiOnly ? 'On' : 'Off'}';
    final error = _error ?? downloads.environmentError;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(label, style: context.tv ? FlickTv.body : FlickText.body),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(FlickTokens.pageGutter, 12, FlickTokens.pageGutter, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Download files: ${_size(downloads.storedBytes)} · Free: ${_size(downloads.freeBytes)}', style: text),
        if (downloads.freeBytes case final free? when free < downloads.remainingBytes || free < (1 << 20))
          Semantics(liveRegion: true, child: Text('Not enough free storage for downloads. Delete chosen files below, then retry.',
            style: text.copyWith(color: context.flick.warning))),
        const SizedBox(height: 8),
        Semantics(toggled: downloads.wifiOnly, child: context.tv
          ? FocusFrame.button(semanticLabel: label, onActivate: _busy ? null : _toggle, child: child)
          : TextButton(onPressed: _busy ? null : _toggle, child: child)),
        Text('Wi-Fi only uses unmetered networks, including Ethernet. Playback has its own network use.', style: text),
        if (!downloads.networkAllowed)
          Semantics(liveRegion: true, child: Text(downloads.wifiOnly ? 'Downloads waiting for Wi-Fi or an unmetered network.'
            : 'Downloads waiting for a connection.', style: text.copyWith(color: context.flick.warning))),
        Text('Unknown sizes may run out of space. Delete chosen files from their download menus to free space.', style: text),
        if (error != null) ...[
          Semantics(liveRegion: true, child: Text(error, style: text.copyWith(color: context.flick.danger))),
          TvControl(child: TextButton(onPressed: downloads.refreshEnvironment, child: const Text('Refresh download storage'))),
        ],
      ]),
    );
  });
}
