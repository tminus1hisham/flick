# Flick: project handoff

Flick is a Flutter 3.41 / Dart 3.11 Android app (package `flick`, Material 3, dark "Afterglow" theme). It is a Stremio-style streaming app: Cinemeta catalogs, addon streams (Torrentio built in), torrents through a native libtorrent4j engine, direct URL streams, subtitles, and offline torrent downloads. There is no Jellyfin and no account (user decision, 2026-10-29). One user, on a phone, often on flaky Wi-Fi.

This file is the shared source for continuing the work in a new session. Read it before you change anything. Update the **Status** and **Next** sections when you finish a piece of work.

## Gates (run before calling anything done)
- `flutter analyze`: must print `No issues found!`
- `flutter test`: 65 tests pass on branch `stremio-only`.
- `flutter build apk --debug`: this is the only check that compiles the Kotlin (`android/app/src/main/kotlin/dev/local/flick/`). Kotlin unit tests: `android/gradlew -p android :app:testDebugUnitTest`.
- Design rules: `python ~/.claude/skills/build-mobile/scripts/gates.py .`. New files must have zero hits (`lib/kit/` is exempt by design). Older files (player.dart, torrent.dart, theme.dart) have known hits; that is expected.
- `PlayerScreen` can't be pumped in `flutter test` because media_kit needs native libmpv. Put player logic in pure helpers or getters and test those (see test/player_test.dart).
- Emulator: AVD `Pixel_9a` (not `Pixel_9a_Guardian`, another project's). media_kit forces software rendering on emulators, so video frames can stay black while playback progresses; judge by the time readout. Use public-domain titles for torrent tests (The Kid, 1921).

## Branches and history
- `main`: the UI revamp ("Afterglow", REVAMP_PLAN.md).
- `discover`: addon streaming (Discover, Title, Streams, Sources, torrents, subtitles). Not merged.
- `guest`: optional sign-in on top of `discover` (design/guest.md). Superseded: the user then dropped Jellyfin and accounts.
- `stremio-only`: current. Branched from `guest`: Jellyfin, accounts and Jellyfin downloads removed; Torrentio built in; offline torrent downloads. Not merged. Merge only when the user asks.
- Untracked and deliberately not committed: the 3 large mockups `design/mockups/{d3-watchhub,d4-sources-bundled,player-subtitles}.png`, the test torrent `ED0AFBC1….torrent`, and `assets/posters/p09–p12.webp` (another session's).

## Architecture
| File | Holds |
|---|---|
| `lib/addons.dart` | Stremio addon client: manifest / catalog / meta / stream / subtitles over `http`, 15 s timeout. Bundled snapshots: Cinemeta (locked), Public Domain Movies, WatchHub, **Torrentio** (on by default), OpenSubtitles v3; a link-added copy of a bundled addon is dropped on load. Every network failure becomes `AddonError.unreachable`. `describe()` parses stream text. `magnetFor()` adds `tr=` trackers, and `fallbackTrackers` when a stream has none (Torrentio sends none; DHT alone never delivered metadata on the emulator). |
| `lib/state.dart` | Globals: `addons` (not final, tests swap it), `saved`, `downloads`. |
| `lib/saved.dart` | `Saved`: device favourites (`MetaPreview` list) and likes, shared_preferences. No account. |
| `lib/downloads.dart` | Offline downloads registry (`Download`, `DownloadState`, `Downloads`): JSON in shared_preferences, engine ids per process, `load()` re-adds unfinished downloads, polls `progress` every second while any is active. Test seam: `Downloads({engine, dirFor})`, fake via `implements TorrentEngine`. |
| `lib/playback.dart` | `Playback` record and `play(context, stream, playback)`: externalUrl → ACTION_VIEW; url → `PlayerScreen`; infoHash → `TorrentScreen`. |
| `lib/torrent.dart` | `TorrentEngine` on MethodChannel `flick/torrent`: add / status / files / stream / stopStream / release / remove, plus download / progress / pause / resume / delete / requestNotifications. `isMagnet`, `isVideo`, `guessFile`. Streaming data lives in `<cache>/flick-torrents/s*`, downloads in `<filesDir>/downloads/<hash>`. |
| `android/.../Torrents.kt` | libtorrent4j session. `add` reuses a live entry with the same hash. `release` removes after 60 s unless the entry is **pinned** (a download). The first-add sweep only touches `<cache>/flick-torrents`. `download` moves a streaming entry into the downloads folder and pins it; done = all pieces verified, then paused. On engine detach, pinned entries are removed without deleting files. |
| `android/.../DownloadService.kt` | dataSync foreground service while any pinned download is active ("Downloading N" + percent), 2 s ticker; sweep/inside-downloads helpers unit-tested in `android/app/src/test/.../DownloadsTest.kt`. Swiping the app away stops downloads until the next launch re-adds them. |
| `android/.../StreamServer.kt` | Loopback HTTP server: Range requests, piece deadlines over 16 MB, hash verification before serving. |
| `lib/main.dart` | Shell: Discover + Downloads (NavigationBar). No login. |
| `lib/screens/discover.dart` | Discover: poster grid, Movies/Series, catalog chips plus a Favourites chip, search on submit, "Stream a link" in the header. |
| `lib/screens/title.dart` | Title (movie streams inline; series seasons/episodes) and Streams (one episode). Favourite/like toggles, stream groups per source, `DownloadButton` on torrent rows only, hero line while a download runs. |
| `lib/screens/downloads.dart` | Downloads tab (Codex visual layer): storage line, rows with progress/paused/ready/failed, delete via kit sheet; a ready row plays the local file. |
| `lib/screens/torrent.dart` | Torrent start screen; `download: true` registers a download and pops instead of playing. |
| `lib/screens/player.dart` | media_kit player, the only dart-formatted file. Headers, recovery overlay ("Back" for local files), tracks panel with OpenSubtitles fetched in Dart without stream headers, device-language auto-pick. |
| `lib/kit/` | `sheet.dart` (`showFlickSheet`), `toggle.dart` (`ToggleAction`), `download_button.dart`. |

## Design sources (approved; follow them, don't reinvent)
- `design/RULES.md`: hard UI rules (Afterglow tokens only; no raw colours, `showDialog`, `SnackBar`, `CircularProgressIndicator` in new code; 48 dp; reduced motion).
- `design/downloads.md` + `design/downloads-visual.md` (Codex): offline downloads.
- `design/brief.md`, `design/spec.md`, `design/codex-visual.md`, `design/codex-pieces.md`, `design/decisions.md` (wins over Codex docs). `design/guest*.md` are historical.
- `REVAMP_PLAN.md`: the Afterglow direction and tokens.

## How the user works
- **Roles:** Claude is senior UX designer, reviewer and orchestrator; Codex CLI is chief UI designer and co-builder. Show the user both voices.
- **Codex on this Windows machine** can't run shell commands (sandbox "Access is denied"). Use bridge mode: `python ~/.claude/skills/build-mobile/scripts/codex_files.py pack` into stdin (set `PYTHONIOENCODING=utf-8`), and ask for `=== FILE: … ===` blocks in the reply. If it answers with a review instead, resume its session and say it needs no shell.
- **No new packages** (deps now: http, shared_preferences, media_kit, path_provider). Mobile features go through the `build-mobile` skill.
- **Don't run `dart format` on files other than player.dart.**
- On Windows, a worktree with long `build/` paths won't delete with `git worktree remove`: `git worktree prune`, then PowerShell `Remove-Item -LiteralPath '\\?\C:\...' -Recurse -Force`.
- `lib/addons.dart` has one `// ignore: valid_regexps` on the emoji regex; leave it.
- Torrentio lists mostly copyrighted releases; test with public-domain titles only.

## Status (2026-10-29)
Emulator-verified on `stremio-only` (Pixel_9a, debug APK):
- Opens straight into Discover (no login). Torrentio rows on titles; Torrentio torrents play (time advances, subtitles auto-load).
- Downloads: ⤓ on a torrent row → TorrentScreen download mode ("The Kid") → back on the title with a progress ring → notification permission prompt → Downloads row with live % / speed / peers → continues in the background ("Downloading 1" notification) → Ready · 859.4 MB → plays in airplane mode → delete via confirm sheet frees the space.
- Not verified: an unfinished download resuming after a relaunch (unit-tested only); streaming a paused download.

## Next
1. Device check of relaunch-resume (start a download, swipe the app away, reopen).
2. A fresh review (code + design critic) of the downloads work (`git diff c019cb3..HEAD`), since it hasn't had one.
3. Known gaps: Torrentio rows repeat their metadata line (raw "190 6.91 GB YTS" above the formatted one, stray "/" lines) in `describe()`; the pinned back/Sources bar has no backdrop when scrolled; streaming a paused download stalls; a failed `moveStorage` isn't reported; polling also runs in the background; subtitle downloads have no size cap; Discover search is on submit; deleting takes two sheets (a one-item menu, then the confirm) where one would do.
4. Deferred by the user: YouTube addon, "Up next".
