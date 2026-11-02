import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../downloads.dart';
import '../kit/sheet.dart';
import '../kit/progress.dart';
import '../kit/focus.dart';
import '../kit/tv_surface.dart';
import '../state.dart' show downloads;
import '../theme.dart';
import '../widgets.dart' show NetImage, Skeleton;

/// Downloads tab body. The app shell owns the heading and bottom navigation.
///
/// [isLoading] represents registry hydration, never an empty-list inference.
/// [isOffline] comes from the host's connection state; zero peers is not offline.
class NativeDownloadsScreen extends StatelessWidget {
  const NativeDownloadsScreen({
    super.key,
    required this.onPlay,
    this.isLoading = false,
    this.isOffline = false,
    this.controls,
  });

  final ValueChanged<Download> onPlay;
  final bool isLoading;
  final bool isOffline;
  final Widget? controls;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final items = downloads.items;
          final stored = items.fold<int>(
            0,
            (sum, d) => sum + _storedBytes(d),
          );

          return ColoredBox(
            color: FlickTokens.background,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: controls != null ? EdgeInsets.zero : const EdgeInsets.fromLTRB(
                    FlickTokens.pageGutter,
                    FlickTokens.grid * 4,
                    FlickTokens.pageGutter,
                    FlickTokens.grid * 5,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: controls ?? (isLoading
                        ? Semantics(
                            label: 'Loading downloads',
                            child: const ExcludeSemantics(
                              child: _StillSkeleton(
                                child: Skeleton(
                                  width: FlickTokens.grid * 48,
                                  height: FlickTokens.grid * 4,
                                  radius: FlickTokens.grid,
                                ),
                              ),
                            ),
                          )
                        : Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: 'Flick downloads · '),
                                TextSpan(
                                  text: _size(stored),
                                  style: streamMonoStyle.copyWith(
                                    color: FlickTokens.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            style: FlickText.metadata.copyWith(
                              color: FlickTokens.textSecondary,
                            ),
                          )),
                  ),
                ),
                if (isLoading)
                  SliverList.list(
                    children: const [
                      _DownloadSkeleton(),
                      _DownloadSkeleton(),
                      _DownloadSkeleton(),
                    ],
                  )
                else if (items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyDownloads(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FlickTokens.pageGutter,
                    ),
                    sliver: SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final d = items[index];
                        return Padding(
                          padding: const EdgeInsets.only(
                            bottom: FlickTokens.railGap,
                          ),
                          child: DownloadRow(
                            key: ValueKey((d.hash, d.file)),
                            download: d,
                            onPlay: onPlay,
                            waitingForConnection: isOffline &&
                                (d.state == DownloadState.queued ||
                                    d.state == DownloadState.downloading),
                          ),
                        );
                      },
                    ),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: FlickTokens.pageGutter +
                        MediaQuery.paddingOf(context).bottom,
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// Public for previews. The manager remains the source of download state.
class DownloadRow extends StatefulWidget {
  const DownloadRow({
    super.key,
    required this.download,
    required this.onPlay,
    this.waitingForConnection = false,
  });

  final Download download;
  final ValueChanged<Download> onPlay;
  final bool waitingForConnection;

  @override
  State<DownloadRow> createState() => _DownloadRowState();
}

class _DownloadRowState extends State<DownloadRow> {
  bool _busy = false;
  String? _actionError;

  Future<void> _run(
    Future<void> Function() action, {
    required String failure,
    bool haptic = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await action();
      if (haptic) HapticFeedback.selectionClick();
    } catch (_) {
      if (mounted) setState(() => _actionError = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _more() async {
    if (_busy) return;
    final d = widget.download;
    final remove = await showFlickSheet<bool>(
      context,
      (sheetContext) => _sheet(
        title: d.playback.title,
        children: [
          TvControl(child: TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: FlickTokens.danger,
              animationDuration: _duration(sheetContext),
            ),
            onPressed: () => Navigator.pop(sheetContext, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete download'),
          )),
          TvControl(child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: FlickTokens.textSecondary,
              animationDuration: _duration(sheetContext),
            ),
            onPressed: () => Navigator.pop(sheetContext, false),
            child: const Text('Cancel'),
          )),
        ],
      ),
    );
    if (remove != true || !mounted) return;

    final confirmed = await showFlickSheet<bool>(
      context,
      (sheetContext) => _sheet(
        title: 'Delete download?',
        children: [
          Text(
            d.playback.title,
            style: FlickText.cardTitle,
          ),
          const SizedBox(height: FlickTokens.grid * 2),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Frees '),
                TextSpan(
                  text: _size(_storedBytes(d)),
                  style: monoStyle,
                ),
                const TextSpan(
                  text: ' on this device. You’ll need to download it again '
                      'to watch offline.',
                ),
              ],
            ),
            style: FlickText.body.copyWith(
              color: FlickTokens.textSecondary,
            ),
          ),
          const SizedBox(height: FlickTokens.grid * 6),
          TvControl(child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FlickTokens.danger,
              foregroundColor: FlickTokens.background,
              animationDuration: _duration(sheetContext),
            ),
            onPressed: () => Navigator.pop(sheetContext, true),
            child: const Text('Delete download'),
          )),
          const SizedBox(height: FlickTokens.grid * 2),
          TvControl(child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: FlickTokens.textSecondary,
              animationDuration: _duration(sheetContext),
            ),
            onPressed: () => Navigator.pop(sheetContext, false),
            child: const Text('Cancel'),
          )),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => downloads.delete(d),
      failure: 'Couldn’t delete this download. Try again from its menu.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.download;
    final ready = d.state == DownloadState.done;
    final active = d.state == DownloadState.downloading ||
        d.state == DownloadState.queued;
    final paused = d.state == DownloadState.paused;
    final failed = d.state == DownloadState.failed;
    final waiting = (widget.waitingForConnection || d.waiting) && active;
    final progress = d.total > 0
        ? (d.bytes / d.total).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final tint = ready
        ? context.flick.success
        : failed
            ? context.flick.danger
            : paused || waiting
                ? context.flick.warning
                : FlickTokens.progress;
    final subtitle = d.playback.subtitle?.trim();
    final episode = [
      if (d.playback.season != null) 'S${d.playback.season}',
      if (d.playback.episode != null) 'E${d.playback.episode}',
    ].join(' ');
    final secondary = subtitle != null && subtitle.isNotEmpty
        ? subtitle
        : episode;

    final status = switch (d.state) {
      DownloadState.queued =>
        waiting ? (downloads.wifiOnly ? 'Waiting for Wi-Fi / unmetered network' : 'Waiting for connection') : 'Queued',
      DownloadState.downloading => waiting
          ? (downloads.wifiOnly ? 'Waiting for Wi-Fi / unmetered network' : 'Waiting for connection')
          : '${d.total > 0 ? '${(progress * 100).floor()}%' : 'Downloading'}'
              ' · ${_size(d.rate)}/s · ${d.peers} peers',
      DownloadState.paused => 'Paused',
      DownloadState.done => 'Ready · ${_size(d.total > 0 ? d.total : d.bytes)}',
      DownloadState.failed =>
        'Failed: ${(d.error ?? '').trim().isEmpty ? 'Couldn’t download this file.' : d.error!.trim()}',
    };

    return RevealArea(child: Padding(
      padding: EdgeInsets.symmetric(vertical: context.tv ? FlickTv.gridPad : 0),
      child: Material(
      color: FlickTokens.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FlickTokens.controlRadius),
        side: BorderSide(
          color: ready
              ? context.flick.success.withValues(alpha: 0.24)
              : FlickTokens.outline.withValues(alpha: 0.48),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(FlickTokens.railGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    button: ready,
                    label: [
                      d.playback.title,
                      if (secondary.isNotEmpty) secondary,
                      if (ready) 'Play offline',
                    ].join(', '),
                    onTap: ready ? () => widget.onPlay(d) : null,
                    excludeSemantics: true,
                    child: TvControl(child: InkWell(
                      borderRadius: BorderRadius.circular(
                        FlickTokens.artworkRadius,
                      ),
                      excludeFromSemantics: true,
                      onTap: ready ? () => widget.onPlay(d) : null,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: FlickTokens.grid * 21,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Poster(download: d, ready: ready),
                            const SizedBox(width: FlickTokens.railGap),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.playback.title,
                                    style: context.tv ? FlickTv.railHeading : FlickText.cardTitle,
                                  ),
                                  if (secondary.isNotEmpty) ...[
                                    const SizedBox(
                                      height: FlickTokens.grid,
                                    ),
                                    Text(
                                      secondary,
                                      style: streamMonoStyle.copyWith(
                                        color: FlickTokens.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (ready) ...[
                                    const SizedBox(
                                      height: FlickTokens.grid * 2,
                                    ),
                                    Text(
                                      'Play offline',
                                      style: FlickText.metadata.copyWith(
                                        color: context.flick.success,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )),
                  ),
                ),
                TvControl(child: IconButton(
                  tooltip: 'More actions for ${d.playback.title}',
                  style: IconButton.styleFrom(
                    animationDuration: _duration(context),
                  ),
                  onPressed: _busy ? null : _more,
                  icon: const Icon(Icons.more_horiz_rounded),
                )),
              ],
            ),
            const SizedBox(height: FlickTokens.railGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    ready
                        ? Icons.check_circle_outline_rounded
                        : failed
                            ? Icons.error_outline_rounded
                            : waiting
                                ? Icons.wifi_off_rounded
                                : paused
                                    ? Icons.pause_rounded
                                    : active &&
                                            d.state == DownloadState.queued
                                        ? Icons.schedule_rounded
                                        : Icons.south_rounded,
                    size: FlickTokens.grid * 4,
                    color: tint,
                  ),
                ),
                const SizedBox(width: FlickTokens.grid * 2),
                Expanded(
                  child: Text(
                    status,
                    style: (d.state == DownloadState.downloading && !waiting ||
                                ready
                            ? streamMonoStyle
                            : FlickText.metadata)
                        .copyWith(color: tint),
                  ),
                ),
              ],
            ),
            if (active || paused) ...[
              const SizedBox(height: FlickTokens.railGap),
              FlickProgress(value: progress, color: tint),
            ],
            if (active || paused || failed) ...[
              const SizedBox(height: FlickTokens.grid * 2),
              Align(
                alignment: Alignment.centerLeft,
                child: TvControl(child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: failed
                        ? context.flick.danger
                        : FlickTokens.textPrimary,
                    animationDuration: _duration(context),
                  ),
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => active
                                ? downloads.pause(d)
                                : downloads.resume(d),
                            failure: active
                                ? 'Couldn’t pause. Try again.'
                                : 'Couldn’t resume. Try again.',
                            haptic: true,
                          ),
                  icon: AnimatedSwitcher(
                    duration: _duration(context),
                    switchInCurve: FlickTokens.curveIn,
                    switchOutCurve: FlickTokens.curveOut,
                    child: Icon(
                      active
                          ? Icons.pause_rounded
                          : failed
                              ? Icons.refresh_rounded
                              : Icons.play_arrow_rounded,
                      key: ValueKey(d.state),
                    ),
                  ),
                  label: Text(
                    _busy
                        ? 'Working…'
                        : active
                            ? 'Pause download'
                            : failed
                                ? 'Retry'
                                : 'Resume download',
                    semanticsLabel: _busy
                        ? 'Updating download'
                        : active
                            ? 'Pause download'
                            : failed
                                ? 'Retry download'
                                : 'Resume download',
                  ),
                )),
              ),
            ],
            if (_actionError != null) ...[
              const SizedBox(height: FlickTokens.grid * 2),
              Semantics(
                liveRegion: true,
                child: Text(
                  _actionError!,
                  style: FlickText.metadata.copyWith(
                    color: context.flick.danger,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    )));
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.download, required this.ready});

  final Download download;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final poster = download.poster?.trim();
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FlickTokens.artworkRadius),
        child: SizedBox(
          width: context.tv ? 88 : FlickTokens.grid * 14,
          height: context.tv ? 132 : FlickTokens.grid * 21,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(
                color: FlickTokens.surface2,
                child: Icon(
                  Icons.movie_outlined,
                  color: FlickTokens.textSecondary,
                ),
              ),
              if (poster != null && poster.isNotEmpty)
                NetImage(poster, icon: false),
              if (ready)
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    margin: const EdgeInsets.all(FlickTokens.grid),
                    padding: const EdgeInsets.all(FlickTokens.grid),
                    decoration: BoxDecoration(
                      color: context.flick.playBg,
                      borderRadius: BorderRadius.circular(
                        FlickTokens.artworkRadius,
                      ),
                    ),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: FlickTokens.grid * 4,
                      color: context.flick.playFg,
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

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(FlickTokens.pageGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: FlickTokens.grid * 20,
                height: FlickTokens.grid * 20,
                decoration: BoxDecoration(
                  color: FlickTokens.surface1,
                  borderRadius: BorderRadius.circular(
                    FlickTokens.modalRadius,
                  ),
                  border: Border.all(color: FlickTokens.outline),
                ),
                child: const Icon(
                  Icons.download_for_offline_outlined,
                  size: FlickTokens.grid * 8,
                  color: FlickTokens.textSecondary,
                ),
              ),
              const SizedBox(height: FlickTokens.sectionGap),
              Semantics(
                header: true,
                child: const Text(
                  'Nothing downloaded yet.',
                  textAlign: TextAlign.center,
                  style: FlickText.railHeading,
                ),
              ),
              const SizedBox(height: FlickTokens.grid * 2),
              Text(
                context.tv ? 'Choose Download on a source to watch it offline.' : 'Tap ⤓ on a torrent to keep it on your phone.',
                semanticsLabel:
                    context.tv ? 'Choose Download on a source to watch it offline.' : 'Tap Download on a torrent to keep it on your phone.',
                textAlign: TextAlign.center,
                style: FlickText.body.copyWith(
                  color: FlickTokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Static skeletons also prevent shimmer implementations from animating.
class _StillSkeleton extends StatelessWidget {
  const _StillSkeleton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: TickerMode(enabled: false, child: child),
      );
}

class _DownloadSkeleton extends StatelessWidget {
  const _DownloadSkeleton();

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
        child: _StillSkeleton(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              FlickTokens.pageGutter,
              0,
              FlickTokens.pageGutter,
              FlickTokens.railGap,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: FlickTokens.surface1,
                borderRadius: BorderRadius.all(
                  Radius.circular(FlickTokens.controlRadius),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(FlickTokens.railGap),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(
                          width: FlickTokens.grid * 14,
                          height: FlickTokens.grid * 21,
                          radius: FlickTokens.artworkRadius,
                        ),
                        SizedBox(width: FlickTokens.railGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Skeleton(
                                height: FlickTokens.grid * 5,
                                radius: FlickTokens.grid,
                              ),
                              SizedBox(height: FlickTokens.grid * 2),
                              Skeleton(
                                width: FlickTokens.grid * 20,
                                height: FlickTokens.grid * 4,
                                radius: FlickTokens.grid,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: FlickTokens.railGap),
                        Skeleton(
                          width: FlickTokens.minTouchTarget,
                          height: FlickTokens.minTouchTarget,
                          radius: FlickTokens.controlRadius,
                        ),
                      ],
                    ),
                    SizedBox(height: FlickTokens.railGap),
                    Skeleton(
                      height: FlickTokens.grid * 4,
                      radius: FlickTokens.grid,
                    ),
                    SizedBox(height: FlickTokens.railGap),
                    Skeleton(
                      height: FlickTokens.grid,
                      radius: FlickTokens.grid,
                    ),
                    SizedBox(height: FlickTokens.grid * 2),
                    Skeleton(
                      width: FlickTokens.grid * 36,
                      height: FlickTokens.minTouchTarget,
                      radius: FlickTokens.controlRadius,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

Widget _sheet({
  required String title,
  required List<Widget> children,
}) =>
    SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FlickTokens.pageGutter,
          FlickTokens.grid,
          FlickTokens.pageGutter,
          FlickTokens.pageGutter,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: FlickText.railHeading),
            ),
            const SizedBox(height: FlickTokens.grid * 4),
            ...children,
          ],
        ),
      ),
    );

Duration _duration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : FlickTokens.stateDuration;

int _storedBytes(Download d) => d.bytes > 0
    ? d.bytes
    : d.state == DownloadState.done && d.total > 0
        ? d.total
        : 0;

String _size(int bytes) {
  final value = bytes < 0 ? 0 : bytes;
  if (value >= 1 << 30) {
    return '${(value / (1 << 30)).toStringAsFixed(1)} GB';
  }
  if (value >= 1 << 20) {
    return '${(value / (1 << 20)).toStringAsFixed(1)} MB';
  }
  if (value >= 1 << 10) {
    return '${(value / (1 << 10)).toStringAsFixed(1)} KB';
  }
  return '$value B';
}
