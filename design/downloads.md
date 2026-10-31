# Offline torrent downloads: brief + spec

User request (2026-10-29): build offline downloads for torrent streams. Download a movie or an episode fully, list it in Downloads, and play it without internet. Context: Flick no longer has Jellyfin or accounts (branch `stremio-only`). Streams come from addons, mainly Torrentio, which is built in and sends no trackers, so `magnetFor` adds `fallbackTrackers`.

## 1. Brief (UX, Claude)

### Users and jobs
One person on a phone, often on flaky Wi-Fi. Jobs: "save this for the flight or the bus", "watch tonight without buffering", "free up space when done".

### Flow
```
Title (movie) / Streams (episode)
  torrent row ── tap ──────────────► play (as today)
             └─ ⤓ download button ──► TorrentScreen in download mode
                                      (same stages: Starting → Reading torrent details → Choose a video,
                                       auto-picks fileIdx or a sure guess exactly like play)
                                      └─ file chosen ─► download registered, screen pops back to the title.
                                         The row's ⤓ becomes a progress ring; a line under the hero says
                                         "Downloading · see Downloads".
Bottom nav: Discover · Downloads (returns; Discover's header keeps "Stream a link")
Downloads
  row: poster · title · episode line · state line (34% · 2.1 MB/s · 12 peers / Paused / Ready · 1.4 GB / Failed: reason)
  tap a ready row ─► player with the local file (offline, no torrent)
  tap a downloading row ─► nothing new (the row's own controls pause/resume)
  pause / resume button per row; delete via row menu ─► kit sheet "Delete download?" (frees N GB) ─► removed
App backgrounded / screen off ─► downloads continue (foreground service, notification "Downloading 2 · 34%")
App killed and reopened ─► incomplete downloads resume by themselves; finished ones stay playable
```

### Screen inventory (delta)
1. **Stream row download button**: a trailing 48dp ⤓ on torrent rows only (`infoHash` streams), never on URL or "where to watch" rows. States: idle ⤓ / downloading (progress ring) / done (✓). The row tap still plays (decisions.md: the whole row is the play target; this is a separate action, not a chevron).
2. **TorrentScreen download mode**: same screen and stages, titled with the title (not "Stream a link"). After the file is chosen it registers the download and pops; no player.
3. **Downloads tab** (rebuilt): list of downloads with the states above, a storage line ("Flick downloads · 3.2 GB"), and an empty state ("Nothing downloaded yet. Tap ⤓ on a torrent to keep it on your phone.").
4. **Delete confirm**: a kit sheet (showFlickSheet), because delete loses data that may have taken an hour on bad Wi-Fi.

### State matrix
| Piece | Loading | Empty | Error | Offline | Success |
|---|---|---|---|---|---|
| Row ⤓ | ring while registering | n/a | button back to ⤓; inline error on TorrentScreen (as play) | TorrentScreen's existing "Couldn't play this torrent" with Retry | ring → ✓ |
| Downloads list | skeleton rows on first load | empty state above | row "Failed: <reason>" + Retry | downloading rows say "Waiting for connection"; ready rows play | rows |
| Ready row playback | player opens from file | n/a | "File missing" row state if the file is gone | plays | plays |

### Interaction notes
- No stock dialogs or snackbars: delete uses the kit sheet; feedback is inline (row state, hero line).
- Progress updates once a second; numbers in `monoStyle`/`streamMonoStyle` so they don't jitter.
- Haptics: lightImpact when a download is registered and when it completes while the app is open; selectionClick on pause/resume.
- 48dp targets, spoken labels ("Download", "Pause download", "Resume download", "Delete download"), progress exposed as a value.
- Reduced motion: the ring has no spin animation; it fills.

### Allowed to scroll
Downloads list (long list). Everything else unchanged.

### Out of scope (ponytail)
- Wi-Fi-only switch, storage cap, download queue order, several files from one torrent at once, streaming a file while it downloads, subtitles offline (OpenSubtitles needs internet; embedded tracks still work).

## 2. Spec (code contract)

### Native (android/.../Torrents.kt, plus a small foreground service)
Downloads live in `<filesDir>/downloads/<infoHash>/`. They must never be in the streaming session folder: `add` sweeps sibling session folders at start.
- `add(magnet, dir)` unchanged. Dart passes the downloads folder for a download.
- `download(id, file)`: every piece of `file` at DEFAULT priority, everything else IGNORE, no sequential flag, no deadlines. Marks the entry `pinned`: `release` and the 60 s timer never remove a pinned entry. If the live entry with this hash sits in the streaming folder, `moveStorage` it to the downloads folder first.
- `progress(id)`: `{bytes, total, rate, peers, state: downloading|paused|done|error, error}` for the pinned file (`fileProgress`).
- `pause(id)` / `resume(id)`.
- `delete(id)`: remove the torrent and delete its files.
- Foreground service (type dataSync, permission already in the manifest): running while any pinned entry is still downloading. Notification "Downloading N · P%". Stops when none are left. POST_NOTIFICATIONS is already declared; ask at the first download on Android 13+.
- Completion: when the pinned file reaches 100 % and hash-checks, the state is `done` and the entry keeps seeding nothing: pause it.

### Dart
- `lib/downloads.dart` (new; the old Jellyfin one is gone):
  ```dart
  enum DownloadState { queued, downloading, paused, done, failed }
  class Download { String hash, magnet; int file; Playback playback; String? poster; String path; DownloadState state;
                   int bytes, total, rate, peers; String? error; }
  class Downloads extends ChangeNotifier {
    List<Download> items;
    Future<void> load();      // registry from shared_preferences; re-adds incomplete downloads to the engine
    Future<void> start(AddonStream s, Playback p, int file, {String? poster});
    Future<void> pause(Download d); Future<void> resume(Download d); Future<void> delete(Download d);
    Download? of(String hash, int file);
  }
  ```
  Polls `progress` every second while any download is active and the app is in the foreground. The global `downloads` lives in state.dart and is loaded in main().
- Ready playback: `PlayerScreen(source: d.path, playback: d.playback)` (the addon/URL path without headers). The player's recovery overlay must not offer "choose another source" for a local file.
- TorrentScreen: `TorrentScreen(stream, playback, download: true)` registers and pops instead of opening the player.

### Motion
Existing tokens only: `stateDuration` (ring/✓ swap), `sheetDuration` (delete sheet), `MediaQuery.disableAnimationsOf`.

### Gates
analyze clean · all tests · `flutter build apk --debug` · gates.py zero hits in new files · unit tests for the registry (persist/reload, re-add on load, delete) and for `Download` state mapping · emulator acceptance with The Kid (1921, public domain): download, background the app, finish, airplane mode, play.
