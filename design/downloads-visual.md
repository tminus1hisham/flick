# Offline downloads · Afterglow

Use the approved theme unchanged. Downloads are a quiet shelf: inset surface1 cards, portrait artwork, generous title space, compact monospaced telemetry, and a thin progress rail. Red marks work in progress; success green marks playable files. Warning amber means paused or waiting. Danger lavender belongs to failure and destructive confirmation.

The tab shell supplies the “Downloads” AppBar. The body supplies storage, registry skeletons, empty state, and download rows. There is no account dependency.

## Stream row placement

Import:

```dart
import '../downloads.dart';
import '../kit/download_button.dart';
import '../state.dart' show downloads;
```

The existing `_Press` excludes descendant semantics. Do not put DownloadButton inside it: that would hide the independent download action from screen readers.

Replace the outer `_Press` with a bordered `Row`. Move the existing quality badge, release lines, and telemetry into the expanded `_Press`. DownloadButton is its sibling. Both share the row's visual surface; tapping the button cannot trigger play.

This helper is an exact placement wrapper for `_StreamRow`. `content` is the existing quality/description Row, without its outer Container. `playLabel` is the existing spoken stream description.

```dart
Widget streamRowFrame({
  required String playLabel,
  required Widget content,
  required VoidCallback onPlay,
  required Widget? downloadAction,
}) {
  return DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(
        bottom: BorderSide(color: FlickTokens.outline),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Press(
            label: playLabel,
            onTap: onPlay,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: FlickTokens.minTouchTarget,
              ),
              padding: const EdgeInsets.fromLTRB(
                FlickTokens.pageGutter,
                FlickTokens.railGap,
                FlickTokens.railGap,
                FlickTokens.railGap,
              ),
              child: content,
            ),
          ),
        ),
        if (downloadAction != null)
          Padding(
            padding: const EdgeInsets.only(
              right: FlickTokens.pageGutter,
            ),
            child: downloadAction,
          ),
      ],
    ),
  );
}
```

Retain the existing play callback, including its light haptic.

Build the trailing control through this helper. Supply `registered` by matching the selected torrent file; supply `onDownload` using the caller's TorrentScreen download-mode navigation. This keeps navigation and file selection outside the visual component.

```dart
Widget? streamDownloadAction({
  required AddonStream stream,
  required Download? registered,
  required VoidCallback onDownload,
}) {
  if (stream.infoHash == null ||
      stream.url != null ||
      stream.externalUrl != null) {
    return null;
  }

  final d = registered;
  final done = d?.state == DownloadState.done;
  final idle = d == null || d.state == DownloadState.failed;
  final progress = idle || done
      ? null
      : d.total > 0
          ? (d.bytes / d.total).clamp(0.0, 1.0).toDouble()
          : 0.0;

  return DownloadButton(
    progress: progress,
    done: done,
    label: d?.state == DownloadState.failed
        ? 'Retry download'
        : 'Download',
    onPressed: idle ? onDownload : null,
  );
}
```

Wrap the stream-row builder in `ListenableBuilder(listenable: downloads, ...)` so progress updates without refetching streams. For a supplied fileIdx, use `downloads.of(hash, fileIdx)`. With no fileIdx, resolve a matching registered file by hash and playback.videoId; do not assume file zero. Keep the selected file identity after registration.

Queued, paused, and connection-waiting registrations retain their last ring value. Pause/resume lives in Downloads. Their trailing control remains disabled to prevent duplicate registration.

In the existing `_Press`, also change the scale duration to:

```dart
duration: MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : FlickTokens.stateDuration,
```

## Hero handoff

Insert this widget after `_Saving(p)` in the movie hero. Insert it after the episode heading inside the Streams header Column. Pass downloads matching that title or episode, respectively. The host owns switching to the Downloads tab and dismissing pushed title routes.

```dart
class DownloadHandoff extends StatelessWidget {
  const DownloadHandoff({
    super.key,
    required this.matches,
    required this.onOpenDownloads,
  });

  final bool Function(Download) matches;
  final VoidCallback onOpenDownloads;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: downloads,
        builder: (context, _) {
          final active = downloads.items.any(
            (d) =>
                matches(d) &&
                (d.state == DownloadState.queued ||
                    d.state == DownloadState.downloading),
          );
          if (!active) return const SizedBox.shrink();

          return Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: FlickTokens.textPrimary,
                animationDuration:
                    MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : FlickTokens.stateDuration,
              ),
              onPressed: onOpenDownloads,
              icon: const Icon(
                Icons.south_rounded,
                color: FlickTokens.progress,
              ),
              label: const Text(
                'Downloading · see Downloads',
                semanticsLabel: 'Downloading. Open Downloads.',
              ),
            ),
          );
        },
      );
}
```

The handoff occupies normal document flow and wraps naturally at larger text sizes. It has no animated pulse and makes no repeated live-region announcements.

## Bottom navigation

Restore Discover and Downloads in the existing app shell. Preserve the current Discover widget and its “Stream a link” header action. The following shell accepts that existing body and the player's callback.

```dart
class DownloadTabs extends StatefulWidget {
  const DownloadTabs({
    super.key,
    required this.discover,
    required this.onPlay,
    this.isLoading = false,
    this.isOffline = false,
  });

  final Widget discover;
  final ValueChanged<Download> onPlay;
  final bool isLoading;
  final bool isOffline;

  @override
  State<DownloadTabs> createState() => _DownloadTabsState();
}

class _DownloadTabsState extends State<DownloadTabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: _index == 1
            ? AppBar(title: const Text('Downloads'))
            : null,
        body: IndexedStack(
          index: _index,
          children: [
            widget.discover,
            DownloadsScreen(
              onPlay: widget.onPlay,
              isLoading: widget.isLoading,
              isOffline: widget.isOffline,
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          animationDuration:
              MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : FlickTokens.stateDuration,
          onDestinationSelected: (index) {
            if (index == _index) return;
            setState(() => _index = index);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.explore_outlined),
              selectedIcon: Icon(Icons.explore_rounded),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download_rounded),
              label: 'Downloads',
            ),
          ],
        ),
      );
}
```

Import `screens/downloads.dart`, `downloads.dart`, and `theme.dart` in the shell file as appropriate to its location. Use the existing `flickTheme()`; NavigationBar gets its surface1 background, surface2 indicator, activeMarker icon, metadata labels, and height from that theme.

If the existing shell already owns a Scaffold, transplant the destinations and body switching there instead of nesting scaffolds.

## Contract boundaries

- Registry hydration has no loading property in the supplied contract. `isLoading` is an explicit host input. Keep it true until the existing `downloads.load()` completes; do not call load again from this screen. When main awaits load before mounting the app, leave it false.
- The contract has no connection signal. Pass the host's known offline state into `isOffline`; zero rate or zero peers must not imply offline. Ready files remain playable.
- Storage and deletion copy use registered file bytes, falling back to total for completed files. These are rounded file sizes, not filesystem free-space measurements or torrent-cache accounting.
- Retry calls `downloads.resume(d)`. The manager must support resuming a failed entry and report subsequent failures through `state` and `error`.
- Missing files must arrive as `DownloadState.failed` with `error: 'File missing'`. File validation belongs to the manager/player integration.
- `onPlay(d)` is called only for ready artwork/title areas. The host wires local playback. Row controls and the overflow menu remain separate targets.
- Registration and completion light haptics belong to the manager/navigation integration. Pause/resume selection haptics occur after successful actions.
- TorrentScreen stages, notification permission, foreground service, local-player recovery, and navigation handoff are integration work outside these visual files.

## Tokens and icons

| Role | Choice |
| --- | --- |
| Screen / row / control | background / surface1 / surface1 |
| Track / border | surface2 / outline |
| Active / paused or waiting | progress / context.flick.warning |
| Ready / error or delete | context.flick.success / context.flick.danger |
| Title / supporting copy | FlickText.cardTitle / FlickText.metadata |
| Numbers and episode line | streamMonoStyle; monoStyle in deletion copy |
| Page inset / card inset / row gap | pageGutter / railGap / railGap |
| Poster | grid × 14 by grid × 21; artworkRadius |
| Card / control / sheet corner | controlRadius / controlRadius / modalRadius |
| Download / active / done | file_download_outlined / south_rounded / check_rounded |
| Pause / resume / retry | pause_rounded / play_arrow_rounded / refresh_rounded |
| Waiting / queued / failed | wifi_off_rounded / schedule_rounded / error_outline_rounded |
| Overflow / delete | more_horiz_rounded / delete_outline_rounded |

The trailing control is exactly minTouchTarget square. State changes use stateDuration and curveIn/curveOut, with the same 0.97 press scale and fade/scale icon swap as ToggleAction. Progress fills clockwise from twelve o'clock and never rotates. Reduced motion snaps fill and icon changes and suppresses press scaling. Skeletons are static.

At 360×640, only the downloads document scrolls. Row titles, reasons, and telemetry have no fixed text height or ellipsis. Controls sit below telemetry so long failure messages and 1.3× text do not collide with actions. Sheets stack their actions and scroll when needed.

These files are supplied as text only; analyzer, widget checks, build, and design gates have not been run.
