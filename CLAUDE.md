# Flick: project handoff

Flick is a Flutter 3.41 / Dart 3.11 Android app (package `flick`, Material 3, dark "Afterglow" theme). It is a Jellyfin client plus Stremio-style streaming: addon catalogs, torrent streams through a native libtorrent4j engine, direct URL streams, and subtitles. One user, on a phone, often on flaky Wi-Fi.

This file is the shared source for continuing the work in a new session. Read it before you change anything. Update the **Status** and **Next** sections when you finish a piece of work.

## Gates (run before calling anything done)
- `flutter analyze`: must print `No issues found!`
- `flutter test`: 80 tests pass on branch `guest`.
- Kotlin unit tests: `cd android && ./gradlew :app:testDebugUnitTest` (results in `build/app/test-results/`). A fresh worktree first needs `flutter pub get` and the gitignored `android/gradlew*` + `android/gradle/wrapper/gradle-wrapper.jar` copied from the main checkout.
- `flutter build apk --debug`: this is the only check that compiles the Kotlin (`android/app/src/main/kotlin/dev/local/flick/`).
- Design rules: `python ~/.claude/skills/build-mobile/scripts/gates.py .`. New files must have zero hits. Older files (player.dart, widgets.dart, library.dart) have known hits; that is expected.
- `PlayerScreen` can't be pumped in `flutter test` because media_kit needs native libmpv. Put player logic in pure helpers or getters and test those (see test/player_test.dart).

## Branches and history
- `main`: the UI revamp ("Afterglow", REVAMP_PLAN.md).
- `discover`: everything below; not yet merged to main. Head 653e238 + this file. Merge to main only when the user asks.
- `guest`: branched from `discover`; optional sign-in (guest mode). See design/guest.md. Not merged.
- Untracked and deliberately not committed: the 3 large mockups `design/mockups/{d3-watchhub,d4-sources-bundled,player-subtitles}.png` (~1.5 MB each), and the test torrent `ED0AFBC1….torrent` (Rick and Morty S04E02, used as a hash in tests).

## Architecture
| File | Holds |
|---|---|
| `lib/addons.dart` | Stremio addon protocol client: manifest / catalog / meta / stream / subtitles over `http`, 15 s timeout, UTF-8 decoding. Bundled addons are manifest snapshots (Cinemeta locked; Public Domain Movies, WatchHub and OpenSubtitles v3 can be switched on and off). User addons and the switches persist in shared_preferences. Every network failure becomes `AddonException(AddonError.unreachable)`, so the client can't tell offline from an addon that is down. `describe()` parses stream text (quality, seeders, size, origin). `magnetFor()` builds a magnet with `tr=` trackers. `openExternal()` calls the native channel. |
| `lib/state.dart` | Globals: `session`, `downloads`, `addons`. `addons` is not final so tests can swap in a fake. |
| `lib/playback.dart` | `Playback` record (title, subtitle, type, canonical Stremio `videoId` such as `tt123:4:2`, season, episode) and `play(context, stream, playback)`, the only way screens start playback. Routing: externalUrl → Android ACTION_VIEW; url → `PlayerScreen` with headers; infoHash → `TorrentScreen`. |
| `lib/torrent.dart` | `TorrentEngine` (MethodChannel `flick/torrent`: add / status / files / stream / stopStream / release / remove), `isMagnet`, `isVideo`, `guessFile` (Stremio enginefs guessFileIdx: unique SxxEyy match or sole video means sure; otherwise suggest the largest). |
| `android/.../Torrents.kt` | libtorrent4j session. `add` reuses a live entry with the same info-hash. `release` stops streaming and removes the torrent after 60 s (enginefs ENGINE_TIMEOUT); only a re-`add` cancels that. `openExternal` (http/https only) answers on the main thread. All TorrentHandle calls run on the single `ctl` executor under `synchronized(e)` after checking `alive`. |
| `android/.../StreamServer.kt` | Loopback HTTP server: Range requests, piece deadlines over a 16 MB window, and hash verification of each piece before serving it. |
| `lib/screens/discover.dart` | D1 Discover tab (2nd tab): 3-column poster grid, Movies/Series switch, catalog chips, search on submit, paging with skip=n, Hero to Title. Hidden feeds sit inside `HeroMode(enabled: visible)`. |
| `lib/screens/title.dart` | D2 Title (movie: streams inline; series: season chips and episodes) and D3 Streams (one episode). Shared stream list: one group per source, each resolving on its own, per-source Retry, filter chips when there are 2 or more sources, WatchHub "Where to watch" rows. `describeStream` is a test seam. |
| `lib/screens/sources.dart` | D4 Sources at route `/sources`: bundled switches, add by manifest URL with inline errors, remove with an inline Undo row. |
| `lib/screens/torrent.dart` | Torrent start screen (stage spine, peers and speed): auto-opens `fileIdx` or a sure guess, otherwise the file list with "Suggested"; Retry / Choose another source; releases (not removes) the torrent on exit. |
| `lib/screens/account.dart` | Guest mode: `Gate`, `requireSignIn(context, gate, poster:)` (sheet, then pushed Login; the caller applies the action afterwards), `openSignIn`, `SignInSheet`, `ToggleAction` (favourite/like; `onPressed` answers whether state changed, haptics only then), `SignInPrompt` (guest Downloads). |
| `lib/kit/sheet.dart` | `showFlickSheet`: the first kit piece (themed, content-sized, reduced-motion aware). New sheets go through it. |
| `lib/screens/player.dart` | media_kit player, the only dart-formatted file in the repo. Jellyfin playback (`report: true`, streamed or downloaded) behaves as before this work. Addon playback (`PlayerScreen.addonPlayback => !report`) adds request headers, a recovery overlay (only before playback starts or when it ends early), and a tracks panel: audio; subtitles Off / embedded / stream-provided / addon subtitles downloaded in Dart **without** the stream's headers and loaded with `SubtitleTrack.data`; device-language auto-pick once, which never overrides a manual choice. |

## Design sources (approved; follow them, don't reinvent)
- `design/RULES.md`: hard UI rules. Afterglow tokens only (`FlickTokens`, `FlickText`, `context.flick`, `monoStyle`, `streamMonoStyle`). No raw colours, `showDialog`, `SnackBar` or `CircularProgressIndicator` in new screens. Skeletons, not spinners. 48 dp targets. Honour `MediaQuery.disableAnimationsOf`.
- `design/brief.md`: the job, flow map, state matrix and scope.
- `design/spec.md`: protocol contract, Dart API, motion, accessibility, and the "Round 2" Stremio extras.
- `design/codex-visual.md` (D1–D4 geometry), `design/codex-pieces.md` (WatchHub rows, player subtitles panel, bundled Sources), `design/decisions.md` (cuts and overrides; these win over the Codex docs), and `design/mockups/`.
- `REVAMP_PLAN.md`: the Afterglow direction and tokens.

## How the user works
- **Roles:** Claude is senior UX designer, reviewer and orchestrator; Codex CLI is chief UI designer and co-builder. Visual-language calls go to Codex; flows, IA, copy and final review stay with Claude. Show the user both voices.
- **Codex on this Windows machine** can't run shell commands in any sandbox, so it can't read files or run flutter. `codex exec -s workspace-write -C <worktree> -o <reply.md> - < brief.md` can write files. Paste the full source of every file it must edit into the brief, then run analyze and tests yourself. Codex output has needed small lint fixes each round.
- **No new packages** (deps: http, shared_preferences, flutter_secure_storage, media_kit, background_downloader, path_provider). Mobile features go through the `build-mobile` skill (global CLAUDE.md).
- **Parallel building:** one git worktree per maker (`git worktree add ../stremio-<name> -b <branch> discover`). Another session (`stremio-99`) worked on this repo the same day, so check `git worktree list` and ListAgents before you start.
- **Don't run `dart format` on files other than player.dart.** The repo is hand-formatted and a format reflows whole files.
- On Windows, a worktree whose `build/` paths are too long won't delete with `git worktree remove`. Use `git worktree prune`, then PowerShell `Remove-Item -LiteralPath '\\?\C:\...\stremio-<name>' -Recurse -Force`.
- `lib/addons.dart` has one `// ignore: valid_regexps` on the emoji regex. The lint parses it without `unicode: true`; the regex is valid and pinned by tests.

## Status (2026-10-29)
Done on `discover`: Discover / Title / Streams / Sources screens, the addon client with bundled official addons, file guessing, warm torrent reuse, request headers, external links, playback recovery, and the subtitles and audio panel. One fresh review round has been run and all its findings are fixed: a header leak to subtitle hosts, Jellyfin downloads picking up the addon player, a stale call keeping a released torrent alive, false failure screens, subtitle duplicates, and offline copy.

**Not verified:**
- Nothing has run on a device. Subtitle loading assumes mpv returns `track-list` as JSON; media_kit observes it as a node, and mpv prints nodes as JSON.
- The player fix commit 653e238 has not had a second review.

### Guest mode (branch `guest`, 2026-10-29)
Sign-in is optional. First launch shows Login with "Continue as guest" (top right); later launches open the guest Shell (Discover + Downloads). Sign-out lands there too. Favourites and likes: Jellyfin titles save to Jellyfin (`/UserFavoriteItems`, `/UserItems/{id}/Rating`, 10.9+ routes), Discover titles save on the device (`saved` in state.dart, `Saved` in session.dart). Guests hit a sign-in sheet; after signing in, the tapped action completes (and sets, never toggles off). Comments are out (no backend; user's call). Surfaces: Discover "Favourites" chip, Home "Favourites" row. Design: design/guest.md (brief + spec), design/guest-visual.md (Codex), decisions.md last section.
- Review: round 1 (code + design critic) failed and was fixed. Round 2: code PASS-WITH-NITS, design critic PASS (distinct 8, hierarchy 8, motion 8, craft 8, states 8, theme 9, a11y 8, space 8). Nits fixed, except one: tapping a guest's download whose file is gone does nothing (no crash, no feedback).
- **Not ours:** login.dart's `_posters` lists p09–p12.webp, added by another session. Those asset files are untracked. Commit them with that session's work, or drop the 4 lines before merging.
- Not verified on a device.

### Buffering and stable playback (branch `guest`, 2026-10-30)
Plan written with Codex: `~/.claude/plans/come-up-with-a-twinkling-peach.md` (4 phases; Claude overrode Codex on: keep SHA-1 piece check, no `cache-secs=30`, 128/16 MiB cache). Phase 1 done and merged (fresh review: both halves PASS-WITH-NITS, nits fixed):
- StreamServer: a new request no longer cancels other waiting requests (mpv's tail probe used to kill the head request); a waiting request ends only when its own client hangs up (`clientGone` in Http.kt) and counts as progress for the 60 s watchdog.
- Player, addon playback only: the 10 s pre-start fatal timer is gone (failure = mpv idle, re-checked 1 s and 3 s after an early error); `network-timeout` 120 s torrent / 30 s direct; demuxer 128 MiB ahead / 16 MiB back; `cache-pause-wait` 3 s, rising once to 8 s after 2 genuine stalls in 60 s (`PauseWait` in lib/stall.dart). `PlayerScreen.torrent` (engine, id) is passed but only used for the timeout so far.
- **Known gap until Phase 3:** a source that hangs without mpv going idle shows loading forever (no "Try another source" yet). Don't merge to main before Phase 3.
- Not verified on a device; the no-blanket-cancel and watchdog-refresh changes have no test that fails without them (native-only).

## Next
- **Buffering Phase 2** (native piece scheduling: head 4 MiB + last-piece prefetch, bitrate-aware rolling window with `deadline = 1000·k·P/R`, seek = request outside the window and not a tail probe → `clearPieceDeadlines`, new channel method `bitrate`) and **Phase 3** (buffering overlay via build-mobile, Codex design in the plan: stages, real progress from `player.stream.bufferingPercentage`, peers · speed, "Waiting for connection" via a native `online` method, "Try another source" after 15 s or 3 stalls in 2 min). Then Phase 4: device measurement and tuning.
0. **Guest mode:** device-check: first launch → Continue as guest → Discover; ♥ as guest → sheet → Sign in → back on the title with ♥ on; sign out → guest shell; guest Downloads prompt.
1. **Device acceptance** (APK: `build/app/outputs/flutter-apk/app-debug.apk`):
   - Jellyfin streamed and downloaded playback still works.
   - Discover → "The Kid" (1921, Public Domain Movies) torrent plays end to end.
   - A user-added stream addon plays a series episode.
   - Wi-Fi off mid-load shows the recovery overlay.
   - Subtitles load and switch.
   - Reopening the same stream within 60 s doesn't reconnect, and the data dir is gone after 60 s.
2. Optional second review of 653e238 (player state machine).
3. **P2, deferred by the user:** YouTube (Stremio's YouTube addon `https://v3-channels.strem.io`, `ytId` streams, Cinemeta trailers; Claude and Codex both recommend handing off to the YouTube app via the `openExternal` intent, not embedding). Then "Up next": at 90 % show the next episode and pick the stream with the same `behaviorHints.bingeGroup` (stremio-core next_video).
4. **Known gaps and follow-ups:**
   - No size cap on subtitle downloads.
   - WatchHub loading skeleton rows and the "No services listed" state aren't built.
   - Movie streams wait for meta before querying.
   - Discover search runs on submit, not as you type.
   - Sources can't show "You're offline" separately (needs a connectivity signal).
   - The player overlay copy is generic.
   - Skipped, with reasons: peer-id spoofing, Rar/Zip/Nzb streams (they need Stremio's server), casting, history sync, addon catalogue browsing.
