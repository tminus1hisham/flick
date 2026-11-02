# Improvements

Researched and checked against the source on 2026-11-01. This is a living backlog of unfinished work, ordered by expected user value. Priorities are recommendations, not measured user demand. Source inspection confirms gaps; it does not replace device testing.

## How agents maintain this list

- Read this file before planning app changes and review it before finishing a task.
- Check the current implementation before starting an item. If its completion criteria already work, remove the item instead of rebuilding it.
- Remove an item once implemented and appropriately verified. Do not retain checked boxes or a completed-items archive here; use version history.
- For partial work, keep only the remaining gap. If device verification is outstanding, state that explicitly rather than treating the feature as absent.
- Add concrete, useful improvements discovered during work, with the current gap, user benefit, completion criteria, and relevant source or code evidence. Merge duplicates and keep the list prioritized. Do not add speculative features simply to grow it.
- Adding an idea does not authorize implementing it. Keep unrelated improvements out of the current task.

## Highest priority

### 1. Verify Continue Watching and explicit resume actions on devices

- **Gap:** Continue Watching, explicit Resume/Start Over and provider-scoped custom addon IDs are implemented for addon, Miruro and offline playback. Custom checkpoints retain their owning provider and exact parent title across stream changes, downloads and Up Next, without storing configuration URLs. Native restart/seek behavior, real-provider resolution and physical-device accessibility remain unverified.
- **Benefit:** Return to an unfinished film or episode without finding it and scrubbing manually.
- **Complete when:** Verify Continue Watching against real addon/Miruro sources, then restart/resume, Start Over, seeking back to zero, completion, source changes, failed opens, retries and offline playback on phone/TV; retain live exclusion. Include custom IDs, disabled/removed providers and restored downloads. Verify the implemented controls with TalkBack and a physical remote. Ask before controlling the user's physical phone, as required by `CLAUDE.md`.
- **Start with:** Existing acceptance scenarios in `CLAUDE.md`; do not rebuild the controls. `test/custom_resume_test.dart` covers legacy provider-identity migration, isolation/reinstall, exact parent lookup and Retry, offline/queue/Up Next scope retention, and colliding search IDs on phone/TV. Existing history, Continue Watching, resume-choice, anime and offline tests cover persistence, completion, cancellation, retries and larger text. Native seeking, real-provider behavior and physical-device accessibility remain device checks.

### 2. Verify saved audio and subtitle preferences on devices

- **Gap:** Implemented in `Settings` and the shared player: successful phone/TV audio and subtitle selections save normalized language codes, including an explicit subtitles-off choice. Later videos match fresh tracks by language; Retry keeps the current video's exact choice where available. Embedded offline tracks work without waiting for subtitle servers. Native phone/TV track application and restart/offline acceptance remain unverified.
- **Benefit:** Stop choosing the same language or turning captions off for every episode.
- **Complete when:** On physical phone/TV, verify saved audio/subtitle language and Off after restart, episode change, Retry and offline playback, including a missing preferred language and a failed external subtitle load. Check explicit choices override defaults and controls remain usable with TalkBack, D-pad and larger text. Eleven persistence/selection regressions in `test/player_tracks_test.dart` establish language matching, stored values, fallback, Off and Retry policy; they do not establish native track switching. Tracks without language metadata can be remembered only for the current video.
- **Research:** [Plex language preferences](https://support.plex.tv/articles/204985278-account-audio-subtitle-language-settings/) provide an established example; implement through existing settings and media_kit/mpv, without changing playback engines.

### 3. Verify subtitle timing and readability controls on devices

- **Gap:** Phone/TV panels now provide Earlier/Later/reset timing, remembered text size and dark background/outline choices with a preview and inline Retry. Timing is scoped to a subtitle within the current player session and retained for recognized tracks on playback Retry; new videos and live source changes reset it. Native timing, real caption rendering and physical-device accessibility remain unverified. The existing plain-text renderer flattens ASS styling and does not support image subtitles; the controls state this explicitly.
- **Benefit:** Make readable captions usable even when their timing differs from the video.
- **Complete when:** On physical phone/TV, verify positive/negative timing and reset, subtitle switches/Off, Retry, new episodes/sources and offline playback. Verify size/contrast after app restart, the phone fullscreen-to-panel transition, preview versus actual text, and failed adjustment/save Retry. Check real SRT/ASS/image tracks against the stated limitations, TalkBack, remote focus/reveal and larger text. Implementation and automated checks are in `design/subtitle-adjustments.md` and `test/subtitle_adjustments_test.dart`; do not rebuild the controls. Ask before driving the user's phone.
- **Research:** The existing engine supports [subtitle options](https://mpv.io/manual/stable/#subtitles), including delay, scale and styling. [Plex subtitle offsets](https://support.plex.tv/articles/subtitle-offsets/) illustrate the user-facing timing adjustment; Plex's format restrictions are not assumptions about mpv.

### 4. Finish real-device playback acceptance

- **Gap:** `CLAUDE.md` still records outstanding physical phone/TV checks for live picture/audio, cached live seeking, buffering recovery, native downloads and episode transitions, plus movie queue handoff and live game/server switching. These features exist; their remaining work is verification and fixes for reproduced failures.
- **Benefit:** Catch failures that passing helper tests and an emulator with EGL errors cannot establish.
- **Complete when:** Record device/app versions and results for live audio/video; seeks at cache boundaries and on streams with no seekable range; Wi-Fi interruption/recovery; a dead source; restart with an unfinished download; streaming while downloading; and Up Next handoff. Verify queued movie completion/manual next through direct, torrent, fullscreen and offline routes; real-source failure/retry and restart persistence; live game/server switches, cancellation during resolution and repeated switching without leaked proxies. Verify the implemented mobile queue sheet with real touch dragging/dismissal, rotation, the live-search keyboard and TalkBack resize actions. Queue source/UI/native-session regressions and widget-rendered phone/TV previews are recorded in `design/playback-queue.md`; actual playback remains a device check. Include TalkBack, larger text and D-pad navigation. Keep only failing or unverified scenarios in this item. Respect the handoff's requirement to ask before controlling the user's physical phone and before using paid mobile data.
- **Research:** Android's [TV accessibility guidance](https://developer.android.com/training/tv/accessibility) calls for usable labels, TalkBack support and layouts that accommodate text scaling. Reuse existing tests and the device scenarios in `CLAUDE.md`.

## Next priority

### 5. Verify saved external subtitles with offline downloads on devices

- **Gap:** Completed-download playback now saves/replaces/removes the selected external caption, retains stream-provided candidates and reopens the saved local file after restart across HTTP and both torrent paths. Sidecar metadata, safe replacement/interrupted-save cleanup, per-video deletion and isolated bounded caption requests are implemented. Physical airplane-mode/native playback and accessibility remain unverified; existing ASS/image-renderer limitations still apply.
- **Benefit:** Downloaded content remains accessible without needing a subtitle server connection.
- **Complete when:** On phone/TV, download a video, open it online, select an external subtitle and Save subtitle offline. Restart in airplane mode and verify caption rendering, global Off, language choices and playback Retry without a subtitle-server connection. Verify replacement/removal, video deletion across HTTP/kept/legacy torrents, missing files, storage failures/Retry and interrupted saves on native storage. Check TalkBack, physical remote focus/reveal and larger text. Implementation and automated evidence are in `design/offline-subtitles.md`, `test/offline_subtitles_test.dart` and `test/offline_resume_test.dart`; do not rebuild the feature. Ask before controlling the user's phone.
- **Research:** [Plex Downloads FAQ](https://support.plex.tv/articles/downloads-sync-faq/) describes offline subtitle behavior. Extend Flick's existing download records/player rather than adding another download system.

### 6. Verify download network and storage controls on devices

- **Gap:** Implemented a persisted Wi-Fi-only/unmetered choice across HTTP and native torrent downloads, including restored tasks, network-change handling and visible waits. Downloads shows file usage/free capacity, known-capacity warnings and HTTP/native preflight checks; unknown sizes can still fail during writes. Existing per-file delete menus provide explicit cleanup, and failed HTTP/kept downloads expose Retry. Native background/restart/network switching, real disk-full recovery and physical-device accessibility remain unverified.
- **Benefit:** Avoid unexpected mobile-data use and downloads failing late because storage is full.
- **Complete when:** On phone/TV, verify HTTP and native torrent downloads while switching between metered and unmetered networks, enabling/disabling the choice mid-transfer, backgrounding and restarting the app. Confirm manually paused tasks stay paused. Verify TV Ethernet, unknown Content-Length, insufficient known capacity, disk filling during transfer, cleanup and successful Retry without lost records. Check recovery after long native waits reach Android's foreground-service limits, plus TalkBack, D-pad and larger text. Network restrictions apply to downloads; explicit playback can use its own connection. Keep only failing/unverified scenarios here; do not rebuild the implemented controls.
- **Research:** Android's [offline download guidance](https://developer.android.com/media/media3/exoplayer/downloading-media) describes persistent download state and network requirements. Use this as a behavior reference, not a recommendation to migrate from background_downloader/libtorrent.

### 7. Finish TV layouts for Downloads, Sources and torrent startup

- **Gap:** The handoff explicitly lists these TV-specific layouts as unfinished. TV Discover, Anime, Title, Player and a shared focus system already exist.
- **Benefit:** Make the full app comfortable to operate from a couch with a remote.
- **Complete when:** These screens follow existing TV components/type sizes; every action is reachable with a visible focus indicator; scrolling reveals focused controls; sheets restore focus; Back behaves predictably. Hide raw season-pack paths where a useful episode/title label exists. Verify with D-pad input and larger text.
- **Research:** Android's [TV navigation guidance](https://developer.android.com/design/ui/tv/guides/foundations/navigation-on-tv) emphasizes reachable controls, predictable directions and straightforward Back behavior. Reuse `lib/kit/focus.dart` and existing TV layouts.

### 8. Restore clean validation gates

- **Gap:** `flutter analyze lib test` reports an existing missing-braces lint in `lib/player_keys.dart:17`. The current design checker reports 7 stock-control and 27 raw-colour violations, all also present in committed code; the handoff's older 27-total baseline is stale. Its default theme-directory exemption also misses `lib/theme.dart`.
- **Benefit:** A clean, accurately configured baseline makes new regressions visible without manually comparing every warning.
- **Complete when:** Fix the existing lint, configure the gate to recognize the actual token file, and migrate remaining offending controls/colours through the existing kit/tokens without blanket suppressions. Verify phone/TV controls, accessibility and reduced motion for any UI replacements; update the documented gate results.
- **Evidence:** `lib/player_keys.dart`, `lib/screens/player.dart`, `lib/screens/downloads.dart`, `lib/screens/speed.dart`, `lib/screens/volume.dart`, and the `gates.py` command in `CLAUDE.md`.

### 9. Scope custom title actions in favourites, likes and queue deduplication

- **Gap:** Playback/history and catalog navigation now retain custom content ownership, but `Saved.isFavourite`, `Saved.isLiked` and toggle/remove operations still compare raw IDs. `QueuedMovie.sameMovie` scopes custom IDs to the selected stream provider rather than the owning catalog, so different custom titles using one stream addon can collapse into one queue entry.
- **Benefit:** Saving or queuing one custom title must not select, remove or hide another provider's title with the same ID.
- **Complete when:** Use content ownership for these comparisons while preserving shared canonical IDs. Retain existing saved data without guessing ownership for legacy custom entries; test colliding custom IDs, different stream providers, removal and restart.
- **Evidence:** `lib/saved.dart`, title favourite/like callers in `lib/screens/title.dart`, and `QueuedMovie.sameMovie`/`MovieQueue.contains` in `lib/queue.dart`. This is separate from the completed resume-scoping work.

## Scope notes

Movie playback queues and the live Queue/Server sidebar, favourites/watchlist, movie/series filtering, basic subtitle/audio selection, Up Next/autoplay, buffering feedback/source-switch guidance, download pause/resume/retry and picture-in-picture already exist and are intentionally absent as new-feature suggestions. The items above describe specific remaining gaps. Do not reintroduce removed accounts or Jellyfin based on obsolete handoff entries.
