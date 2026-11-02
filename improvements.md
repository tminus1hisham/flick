# Improvements

Audited against the current source and recorded verification on 2026-11-02. One implementation item remains. Implemented features with outstanding physical-device checks are listed separately; they are not new feature work. Source inspection does not establish device acceptance. Item numbers remain stable for existing references in `CLAUDE.md` and design documents.

## How agents maintain this list

- Read this file before planning app changes and review it before finishing a task.
- Check the current implementation before starting an item. If its completion criteria already work, remove the item instead of rebuilding it.
- Remove an item once implemented and appropriately verified. Do not retain checked boxes or a completed-items archive here; use version history.
- For partial work, keep only the remaining gap. If device verification is outstanding, state that explicitly rather than treating the feature as absent.
- Add concrete, useful improvements discovered during work, with the current gap, user benefit, completion criteria, and relevant source or code evidence. Merge duplicates and keep the list prioritized. Do not add speculative features simply to grow it.
- Adding an idea does not authorize implementing it. Keep unrelated improvements out of the current task.

## Implementation work — next item is 9

### 9. Scope custom title actions in favourites, likes and queue deduplication

- **Gap:** Playback/history and catalog navigation now retain custom content ownership, but `Saved.isFavourite`, `Saved.isLiked` and toggle/remove operations still compare raw IDs. `QueuedMovie.sameMovie` scopes custom IDs to the selected stream provider rather than the owning catalog, so different custom titles using one stream addon can collapse into one queue entry.
- **Benefit:** Saving or queuing one custom title must not select, remove or hide another provider's title with the same ID.
- **Complete when:** Use content ownership for these comparisons while preserving shared canonical IDs. Retain existing saved data without guessing ownership for legacy custom entries; test colliding custom IDs, different stream providers, removal and restart.
- **Evidence:** `lib/saved.dart`, title favourite/like callers in `lib/screens/title.dart`, and `QueuedMovie.sameMovie`/`MovieQueue.contains` in `lib/queue.dart`. This is separate from the completed resume-scoping work.

## Device verification only — features already implemented

Do not rebuild these features when asked for the next implementation item. The current shared tree passes 436 Flutter tests and the Android unit-test gate (45 tests); analysis/design gates are clean and the debug APK builds, as recorded in `CLAUDE.md`. That evidence is not physical-device acceptance. Reuse existing tests and acceptance scenarios. Record device/app versions and results, and retain only failing or unverified scenarios below.

For every relevant scenario, check phone/TV accessibility: TalkBack, larger text, physical remote navigation, visible focus/reveal and focus restoration. Ask before controlling the user's physical phone or using paid mobile data, as required by `CLAUDE.md`.

### 1. Continue Watching and explicit resume actions: device acceptance

- **Already implemented:** Continue Watching, Resume/Start Over and provider-scoped custom IDs across addon, Miruro and offline playback, including source changes and exact parent-title lookup.
- **Remaining:** Real-provider resolution; restart/resume, Start Over, seeking to zero, completion, failed opens/Retry and restored downloads on native phone/TV. Include colliding custom IDs, disabled/removed providers and live exclusion.
- **Evidence:** `lib/history.dart`, `lib/screens/continue_watching.dart`, `lib/screens/resume.dart`, `test/custom_resume_test.dart` and the existing history/resume/offline tests.

### 2. Saved audio/subtitle preferences: device acceptance

- **Already implemented:** Persisted normalized audio/subtitle language, explicit Off, fresh-track language matching, exact current-video choices on Retry and embedded offline tracks.
- **Remaining:** Native track application after restart, episode change, Retry and offline playback; missing preferred language, failed external subtitle loading and explicit choices overriding defaults. Tracks without language metadata are remembered only within the current video.
- **Evidence:** `Settings` in `lib/state.dart`, the shared player, `test/player_tracks_test.dart` and `design/player-preferences.md`.

### 3. Subtitle timing/readability: device acceptance

- **Already implemented:** Earlier/Later/reset, saved text size and background/outline, preview and inline Retry. Timing is session/subtitle-specific, retained for recognized tracks on playback Retry and reset for new videos/live sources.
- **Remaining:** Native positive/negative delay/reset, switches/Off, Retry and offline playback; appearance after restart; phone fullscreen-to-panel transition; preview versus actual rendering; adjustment/save failures. Check SRT/ASS/image tracks against the existing documented limitation: plain-text rendering flattens ASS styling and does not support image subtitles.
- **Evidence:** `lib/subtitles.dart`, `lib/screens/subtitle_adjustments.dart`, `design/subtitle-adjustments.md` and `test/subtitle_adjustments_test.dart`.

### 4. Playback, queues and transitions: device acceptance

- **Already implemented:** Live playback/cached seeking/recovery, movie queues, the mobile queue sheet, live game/server switching and Up Next. Remaining native download checks belong to item 6.
- **Remaining:** Actual live picture/audio, cache-boundary seeks/no seekable range, Wi-Fi interruption/recovery and dead sources. Verify streaming while downloading and Up Next handoff. Check queued movie completion/manual next through direct, torrent, fullscreen and offline routes; real-source failure/Retry and restart persistence. Check live switches/cancellation/repeated switching without leaked proxies. Verify queue-sheet touch dragging/dismissal, rotation, live-search keyboard and TalkBack resize actions.
- **Evidence:** `CLAUDE.md` device scenarios, `design/playback-queue.md` and queue/player regression tests. Emulator audio and widget previews do not establish decoded-video acceptance.

### 5. Saved external subtitles offline: device acceptance

- **Already implemented:** Save/replace/remove the selected external caption from completed-download playback, retained stream candidates, local reopening after restart, safe sidecar cleanup/deletion across HTTP and both torrent paths, and isolated bounded caption requests.
- **Remaining:** Download → open online → select an external subtitle → Save subtitle offline → restart in airplane mode. Verify native rendering, global Off, language choices and Retry without a subtitle-server connection. Check replace/remove/video deletion across all three backends, missing files, native storage failure/Retry and interrupted saves. Renderer limitations are the same as item 3.
- **Evidence:** `lib/offline_subtitles.dart`, `lib/screens/offline_subtitles.dart`, `design/offline-subtitles.md`, `test/offline_subtitles_test.dart` and `test/offline_resume_test.dart`.

### 6. Download network/storage controls: device acceptance

- **Already implemented:** Persisted Wi-Fi-only/unmetered policy for HTTP/native torrents and restored tasks, visible network waits, capacity/usage display, known-size capacity checks, delete/cleanup and failed-download Retry.
- **Remaining:** Metered/unmetered switching and policy changes mid-transfer, TV Ethernet, background/restart transfers, manually paused tasks staying paused, unknown Content-Length, insufficient capacity and disk filling during transfer. Verify cleanup/Retry without lost records and recovery after long native waits reach Android foreground-service limits. Explicit playback uses its own connection; this policy governs downloads.
- **Evidence:** `lib/downloads.dart`, `lib/screens/download_controls.dart`, native `Torrents.kt`/`DownloadService.kt`, `test/downloads_test.dart` and `test/download_controls_test.dart`.

### 7. TV Downloads, Sources and torrent startup: device acceptance

- **Already implemented:** TV safe-area spacing, house headings, larger rows/artwork and TV typography across HTTP/kept/legacy downloads, Sources and torrent startup. Existing Material actions retain their activation behavior with kit focus rings; traversal reveals download/file rows. Sources Remove/Undo preserves focus. Automatic torrent startup uses the episode/title label; manual file choices retain paths to distinguish files. Widget checks cover remote activation, scrolling, menu Back/focus restoration and 1.3× text.
- **Remaining:** Physical Android TV remote and TalkBack checks for mixed download backends and their state changes, deletion/confirmation/cancellation, storage Retry, Sources add/remove/Undo/update/error actions, magnet entry, torrent errors/Retry/Back and returning from playback. Check visible rings/reveal, larger text, reduced motion, keyboard dismissal and shell/route Back behavior on the device.
- **Evidence:** `lib/kit/tv_surface.dart`, the four utility screens, `test/tv_utilities_test.dart`, `test/sources_test.dart`, `test/download_controls_test.dart` and existing shell/offline regressions. No physical device was controlled.

### 8. Migrated player/download controls: device acceptance

- **Already implemented:** Clean analyzer/design gates, explicit token-file configuration, house speed/volume sheets, persistent inline player feedback and a shared download track with an unknown-size skeleton. No gate suppressions or new dependencies. Widget checks cover touch/remote selection, large text, reduced motion, semantics, focus rings and restoration.
- **Remaining:** Physical phone/TV TalkBack and remote checks for speed/volume sheets, Back and focus restoration, including fullscreen playback. Force speed/PiP failures and check feedback visibility, announcement and dismissal; verify known/unknown-size HTTP download progress. Native player mounting/fullscreen behavior is outside widget-test coverage.
- **Evidence:** `design/gates.json`, `lib/screens/player_feedback.dart`, `lib/kit/progress.dart`, `test/validation_controls_test.dart`, existing speed/volume/TV player tests and the gate results in `CLAUDE.md`.

## Scope notes

Movie playback queues and the live Queue/Server sidebar, favourites/watchlist, movie/series filtering, basic subtitle/audio selection, Up Next/autoplay, buffering feedback/source-switch guidance, download pause/resume/retry and picture-in-picture already exist and are intentionally absent as new-feature suggestions. The items above describe specific remaining gaps. Do not reintroduce removed accounts or Jellyfin based on obsolete handoff entries.
