# Anime in Flick: plan

## Do now (user's instruction, 2026-10-30): commit, main, Codex builds, Haiku monitors
1. **Commit.**
   - Code: nothing is uncommitted. Another session committed the player and StreamServer work as `e173553`.
   - Commit `assets/posters/p09–p12.webp` on `guest`. The committed `login.dart:20-23` already references them, so without them the login wall breaks.
   - Leave untracked, per CLAUDE.md: the 3 mockups, the `.torrent` and `.claude/`.
2. **Main.** Fast-forward `main` to `guest` (`git merge --ff-only guest` on main; main is an ancestor, 55+ commits). This merges `discover` + `guest`, which the user has now asked for. Update the CLAUDE.md branch notes in the same commit set.
   - **No git remote is configured**, so there is nothing to push to. Report that, and push only if the user gives a remote URL.
3. **Branch.** Create worktree `../stremio-anime` on branch `anime` from main. Copy in the gitignored `android/gradlew*` and the wrapper jar, then run `flutter pub get`.
4. **Codex builds; a script drives it** so it keeps going when Claude's limits run out. Write `tool/anime_build.ps1` plus step briefs `design/anime/steps/NN-*.md`, each listing the files Codex needs. Codex can't read files here, so the script packs them (`codex_files.py pack`). For each step:
   - `codex exec -s read-only -o reply.md` (bridge mode), then `codex_files.py apply`.
   - Then `flutter analyze`, `flutter test`, `gates.py` (new files only).
   - Green: `git commit -m "anime: step NN …"`. Red: `codex exec resume <id>` with the errors, up to 3 tries.
   - After 3 failed tries: stop and write `design/anime/STATUS.md`.
   - Log to `design/anime/build.log`. Never touches main.
   - Steps:
     - S1 Spike CLI `tool/anime_spike.dart`, run on the PC (residential IP, Dart TLS). It writes `test/fixtures/anime/*.json`. Gate: exit 0 and a `.m3u8` URL in the sources fixture. **If S1 fails, the script stops**: no UI on a dead source.
     - S2 `lib/anime.dart` + `test/anime_test.dart` against the fixtures.
     - S3 the `Progress` store + `PlayerScreen` `start` / progress / `skips` (pure helpers tested).
     - S4 the Torrent streaming switch.
     - S5 extract `_Chips`, `_EpisodeRow`, `_Press` and the skeletons into `lib/kit/` with no behaviour change.
     - S6 A1 Anime segment.
     - S7 A2 Anime title.
     - S8 A3 skip pill + Playback source sheet. Up Next waits for `upnext`.
5. **Haiku monitor.** One `delegate:runner` (Haiku) watches `build.log` with Monitor and reports each step's result and any stop. Caveat: it uses the same Claude account, so if the limits are fully exhausted the monitor stops too. The PowerShell script itself needs no Claude and keeps running.
6. **Left for when Claude is back:** the device spike on the phone (mpv, pru, AES), the `mobile-qa-critic` on S6–S8 (≥ 8), a fresh `delegate:reviewer`, device acceptance, and merging `anime` → main. Codex is building the non-UI steps too, at the user's request; this overrides the usual split where Claude's builders own logic.

## Context
The user wants anime inside Flick, covering watching, saving and later downloading, built from one of two "Miruro API" repos. Claude (UX) and Codex (UI) debated the repos and the UI in two rounds (Codex session `01a18ca5-3307-7992-ba08-7165bb18bb14`). The user then settled three choices:
- **Where anime lives:** a third segment in **Discover** (Movies | Series | Anime). No new tab.
- **Guest saves:** guests still get the **sign-in sheet** when they tap the heart.
- **Downloads:** in **Release 2**, after on-device playback is proven.

Build on a new branch `anime` from `guest`, through the build-mobile pipeline (global CLAUDE.md).

## Debate verdict: repo B (Shineii86/MiruroAPI) as reference code, ported to run on the phone
Both repos wrap the same upstream: `GET miruro.{tv,to,ru,bz}/api/secure/pipe?e=<base64url(JSON{path,method,query,body})>`, which sits behind Cloudflare. Metadata comes from AniList GraphQL.

| | A walterwhite-69 (Python) | B Shineii86 (Node) |
|---|---|---|
| License | none, so we can't copy it | MIT, so we can port it with attribution |
| Last push | 2026-07-03 | 2026-08-25 (v2.3.3) |
| Pipe decoding | base64 → gunzip only | reads `x-obfuscated`; for scheme 2 it XORs with a 16-byte key before gunzip |
| Robustness | no timeout, no cache | 4 mirrors, 15 s timeout, 1/2/4 s backoff, cache |
| Extras | TLS impersonation (curl_cffi) | skip times, VTT subtitles, `download` links, `pru` URL decoding, provider notes (bee/ally serve decoys) |

- **Repo A is out.** It has no license and predates Miruro's obfuscation change (B's v2.2.0), so it is likely broken. Its one lesson is that Cloudflare may fingerprint the client's TLS.
- **Neither repo runs as a server.** Datacenter IPs get 403/444, and B reports decoy segments served to server IPs. A phone has a residential or mobile IP, needs no hosting, and mpv already sends per-stream headers.
- **A Stremio addon wrapper is rejected.** It adds a server and doesn't solve the transport problem (Codex and Claude agree).
- **Codex's corrections, accepted:**
  - "No proxy needed" is unproven, so prove the whole path on the phone first.
  - Headers are per provider, not Miruro's everywhere.
  - Treat WebView as experimental: Turnstile, cookie scope and cookie lifetime are all open.
  - Use one preferred provider plus one fallback, not a fan-out.
  - A `download` field may point to a web page, not a file.
- **Claude override:** B's episode objects do carry `filler` and `fillerType`. Show the filler tag only when the field is present.
- **Risk to flag to the user:** Miruro aggregates unlicensed streams and has changed its obfuscation at least twice, with keys hard-coded in the code. This is personal use only, it will break when Miruro changes, and the failure must stay contained to the Anime segment.

## Phase 0: spike (gate before any UI)
This is a throwaway Dart harness, `tool/anime_spike.dart` plus a debug-only screen, run on the emulator and then on the phone. Record pass or fail for each step in `design/anime.md`:
1. Pipe `episodes` for AniList 20 (Naruto) with Dart `http` and B's headers. Then the scheme-2 decode.
2. `sources` for kiwi and bonk, sub and dub. Then the playback contract: url, type, headers, subtitles, skip, download.
3. In mpv through `PlayerScreen` (with `headers`): play 3 minutes, seek, check child playlists and segments, and check AES-128 key fetches.
4. `pru` URLs: does mpv play them directly, and are `/seg.jpg` segments real media or decoys?
5. A VTT subtitle loads through the existing `SubtitleTrack.data` path.

Ladder if a step fails:
- (a) Dart `http` direct.
- (b) Native Kotlin hidden WebView doing `fetch()` in page context, behind MethodChannel `flick/anime`. If Turnstile needs interaction, show a visible "Connect" screen.
- (c) Playlist and segment rewriting in the existing `StreamServer.kt` loopback, used only if mpv fails on child requests.
- (d) Last resort: an optional "Anime server" URL pointing at a self-hosted repo B on the user's PC.

If nothing passes, stop and report to the user. Don't build the UI.

## Release 1: browse, watch, save, continue

### Data layer: `lib/anime.dart` (new; credits B under MIT)
- **`AniList` client** (GraphQL via `http`): `season`, `trending`, `popular`, `upcoming`, `airing(date)`, `search`, `info(id)`, genres. Cache in memory.
- **`Pipe` client:**
  - Mirrors, the XOR key and the provider allow-list sit in one `const` block.
  - Same timeouts and backoff as B. Episodes cached 5 min, sources 10 min. Requests coalesced.
  - 403/444 and decode failures become `AnimeException(AnimeError.blocked | unreachable | changed)`, mirroring the `AddonException` pattern in `lib/addons.dart`.
- **`resolve(anilistId, ep, lang)`** returns an `AnimeSource {url, headers, subtitles, skips, label, quality}`. It tries the preferred provider (kiwi or bonk, per the spike), then one fallback.
- **Identity:**
  - Title: `anilist:<id>`. Episode: `anilist:<id>:<n>`. AniList splits seasons and specials into separate media, so (id, n) is stable.
  - The sub/dub preference is stored per show in shared_preferences.
- The pure parsers (decode, pru, episode grouping, source contract) are unit-tested with recorded fixtures from the spike.

### Shared stores, used by anime and reusable later
- **`Progress`** (new, in `lib/session.dart` beside `Saved`):
  - Data: `videoId → {pos, dur, at}` in shared_preferences.
  - Watched means ≥ 90 %, and the resume position is kept.
  - Written every 10 s, on pause, on app background and on exit.
- **`PlayerScreen` additions:**
  - A `start` parameter (today it only reads `item.resumePosition`).
  - A progress callback for addon playback.
  - `skips: List<({Duration start, Duration end, String kind})>`.
- **`Saved`:** favourites accept `MetaPreview(type: 'anime', id: 'anilist:<id>')`. Discover's existing type filter keeps them out of Movies and Series. The guest rule is unchanged (`requireSignIn`).

### UI: build-mobile phases 1, 3 (delta), 4, 6, 7, 9 for 3 surfaces
The brief and spec delta go in `design/anime.md`. Codex does the visual layer, Claude does flows, states and copy.
1. **A1: Anime segment in Discover** (`lib/screens/discover.dart`, plus a new `lib/screens/anime.dart` for its body).
   - Discover remembers the last segment. Anime keeps its own state and scroll position.
   - Layout: an anime-scoped search, then chips (This season by default, Airing today, Trending, Popular, Upcoming, Genres, Saved), then the 3-column grid.
   - A "Continue watching" row appears above the grid only when it has items.
   - Each poster gets one secondary line: progress or airing time. Airing times use the phone's timezone and show the absolute time, not only a countdown.
   - May scroll: it is a feed.
2. **A2: Anime title** (new `lib/screens/anime_title.dart`).
   - Uses the existing Title vocabulary. Extract `_Chips`, `_EpisodeRow`, `_Press` and the skeletons from `title.dart` into `lib/kit/` instead of copying them.
   - Header: compact backdrop. Format, status and episode count sit together, with the score below them.
   - One primary **Resume Ep N / Play** button, then the Sub | Dub switch, then the episode list.
   - Episode windows of 50, opened at the next unwatched episode. A "Go to episode" control opens a `showFlickSheet`.
   - Rows show watched ticks and progress, and the filler tag when present.
   - There is no stream list: tapping an episode plays it.
   - May scroll: the whole page, with no nested scroller.
3. **A3: Player additions** (`lib/screens/player.dart`, addon path only).
   - **Skip intro / Skip outro** pill, shown only during valid skip ranges.
   - **Playback source** sheet: switch provider or sub/dub while keeping the position. It is separate from the tracks panel.
   - **Next episode:** plug into the `upnext` branch's `UpNextCard`; its spec is in `stremio-upnext/design/upnext.md`. Anime supplies `upNextAt` (the outro start when known, otherwise its default) and a `resolve()` that returns the next episode from the same provider and language. Wait for `upnext` to merge. One owner for the card and for navigation.
   - When anime opens the player it passes `playback: null`, so no Stremio subtitle addon is queried, and no `torrent` is passed, so no peer stats appear.
   - The connecting state is the existing `BufferingPanel` "Starting". Its "Try another source" button opens the Playback source sheet instead of popping the player.
   - State matrix in the brief: loading, empty, error (blocked / source changed / offline), offline, success for A1, A2 and A3. The anime-down copy names the cause and never touches Discover Movies/Series or Jellyfin.

### Hiding torrents
- Anime screens never show `MagnetButton`, seeders, peers, filter chips or `TorrentScreen`, whatever the switch says.
- **"Torrent streaming"** switch in Sources (`lib/screens/sources.dart`): "Use peer-to-peer sources and show magnet actions." Default on, persisted like the other source switches. When off:
  - `MagnetButton` is hidden (in `main.dart`'s AppBar and in OfflineShell).
  - Streams with an `infoHash` or a magnet URL are filtered out in `title.dart`.
  - `play()` never routes to `TorrentScreen`.
  - Existing downloads stay manageable.

## Release 2: downloads (after Release 1 is stable on the device)
- **Native `HlsDownload.kt`:**
  - Fetches the playlist with the stream's headers and picks the chosen variant.
  - Downloads segments in order and decrypts AES-128 with `javax.crypto`.
  - Concatenates them into one `.ts` file (for fMP4: the init segment plus the fragments).
  - Saves the VTT next to the video. Resumable, with a foreground notification. MethodChannel `flick/hls`.
- **Downloads model:** generalise `lib/downloads.dart` from a Jellyfin `Item` to a small `DownloadEntry {id, title, subtitle, poster, kind}`. Add an anime row ("Ep 5 · Sub · 720p") that plays offline with `report: false` and resumes from `Progress`.
- **Episode actions:** per-episode Download on A2 appears only once the provider's capability has been proven. Season batch download comes later.

## Critical files
- New: `lib/anime.dart`, `lib/screens/anime.dart`, `lib/screens/anime_title.dart`, `lib/kit/*` (extracted widgets), `design/anime.md`, `test/anime_test.dart`, `test/fixtures/anime/*.json`.
- Changed: `lib/screens/discover.dart` (segment), `lib/screens/player.dart` (`start`, progress, skips, source sheet), `lib/session.dart` (`Progress`), `lib/screens/sources.dart` + `lib/main.dart` + `lib/playback.dart` + `lib/screens/title.dart` (torrent switch), `lib/state.dart` (`anime` global, swappable for tests).
- Release 2: `android/.../HlsDownload.kt`, `lib/downloads.dart`, `lib/screens/downloads.dart`.

## Reuse
- `NetImage`, `Skeleton`, `posterGrid`/`GridSkeleton`, `ErrorState`, `SectionHeader`, `friendlyError` (`lib/widgets.dart`)
- `showFlickSheet` (`lib/kit/sheet.dart`)
- `ToggleAction`, `requireSignIn` (`lib/screens/account.dart`)
- `BufferingPanel` / `bufferView` (`lib/screens/buffering.dart`, `lib/stall.dart`)
- `PlayerScreen` headers and `SubtitleTrack.data` loading
- `AddonException` error pattern
- `UpNextCard` (branch `upnext`)

## Verification
- Gates: `flutter analyze` → `No issues found!`; `flutter test` (93 tests plus the new anime tests); `flutter build apk --debug`; `python ~/.claude/skills/build-mobile/scripts/gates.py .` with zero hits in new files.
- Unit tests: pipe decode (plain and scheme 2), pru round trip, episode grouping, source contract, provider fallback order, `Progress` persistence and the 90 % rule, the torrent-switch filter, skip-pill visibility as a pure getter (`PlayerScreen` can't be pumped).
- Widget tests: A1 segment switch, skeleton, blocked state; A2 resume button, episode window, Sub/Dub; A1 and A2 at 360×640.
- `mobile-qa-critic` on A1, A2 and the player additions: every score ≥ 8. A fresh `delegate:reviewer` on the diff.
- Device acceptance (emulator first, then the phone):
  - Naruto ep 1 plays and seeks; Skip intro works.
  - Switching source keeps the position; Sub → Dub works.
  - Continue watching appears and resumes.
  - With Wi-Fi off, the panel waits and then recovers.
  - Torrent switch off: no magnet button and no torrent rows.
  - Jellyfin playback and Discover are unchanged.

## Order
Spike → data layer and tests → shared stores + player hooks → torrent switch → A1 → A2 → A3 (Up Next after `upnext` merges) → critic and review → device pass → Release 2.
