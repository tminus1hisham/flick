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

### 1. Finish Continue Watching and explicit resume actions

- **Gap:** The shared player checkpoints and automatically restores progress by content type/canonical video ID, including Miruro and downloads carrying that identity; live broadcasts are excluded. Discover now exposes viewing history with per-video removal, confirmed clear-all and persistence retry on phone/TV. Continue Watching and explicit Resume/Start Over actions remain absent. Unsupported/custom addon IDs are excluded until collision-safe provider scoping exists. Real playback/restart and physical-device history-control acceptance remain unverified.
- **Benefit:** Return to an unfinished film or episode without finding it and scrubbing manually.
- **Complete when:** Title pages offer Resume and Start Over; Continue Watching opens the correct episode and re-resolves online sources (including Miruro) rather than replaying saved URLs; videos at 95% completion leave that row. Scope noncanonical addon IDs without breaking resume across source changes or offline downloads. Verify restart/resume, seeking back to zero, completion, source changes, failed opens, retries and offline playback on phone/TV; retain live exclusion. Verify the implemented history controls with TalkBack and a physical remote.
- **Start with:** `lib/history.dart`, `lib/screens/history.dart`, `lib/screens/player.dart`, `lib/playback.dart`, and title/discovery/anime/download entry points. Persistence tests cover reload, content identity, completion, deletion/retry, corruption and the 100-video retention bound. Widget tests cover removal, clear confirmation/cancel, retry after the last row disappears, phone/TV routing and remote scrolling/focus at 1.3× text; they do not establish native seek behavior or physical-device accessibility.

### 2. Save audio and subtitle preferences

- **Gap:** `lib/screens/player.dart` chooses initial subtitles using the device locale and holds user selections in player state. There are no persisted audio/subtitle language settings in `Settings`.
- **Benefit:** Stop choosing the same language or turning captions off for every episode.
- **Complete when:** Preferred audio language, subtitle language and subtitles-off preference survive restart and apply to subsequent episodes, Retry and offline playback where matching tracks exist. A missing language falls back safely without preventing playback; explicit user choices win over automatic selection. Persist language/preferences rather than transient track IDs.
- **Research:** [Plex language preferences](https://support.plex.tv/articles/204985278-account-audio-subtitle-language-settings/) provide an established example; implement through existing settings and media_kit/mpv, without changing playback engines.

### 3. Add subtitle timing and readability controls

- **Gap:** The shared player provides subtitle selection, language search and retry, but no app controls for timing offset, text size or appearance.
- **Benefit:** Make readable captions usable even when their timing differs from the video.
- **Complete when:** Phone and TV users can adjust/reset timing and text size, with readable contrast/background options. Remember appearance preferences; scope timing offsets to the relevant video/subtitle pairing so they do not affect unrelated episodes. Handle styled ASS and image subtitle limitations honestly.
- **Research:** The existing engine supports [subtitle options](https://mpv.io/manual/stable/#subtitles), including delay, scale and styling. [Plex subtitle offsets](https://support.plex.tv/articles/subtitle-offsets/) illustrate the user-facing timing adjustment; Plex's format restrictions are not assumptions about mpv.

### 4. Finish real-device playback acceptance

- **Gap:** `CLAUDE.md` still records outstanding physical phone/TV checks for live picture/audio, cached live seeking, buffering recovery, native downloads and episode transitions. These features exist; their remaining work is verification and fixes for reproduced failures.
- **Benefit:** Catch failures that passing helper tests and an emulator with EGL errors cannot establish.
- **Complete when:** Record device/app versions and results for live audio/video; seeks at cache boundaries and on streams with no seekable range; Wi-Fi interruption/recovery; a dead source; restart with an unfinished download; streaming while downloading; and Up Next handoff. Include TalkBack, larger text and D-pad navigation. Keep only failing or unverified scenarios in this item. Respect the handoff's requirement to ask before controlling the user's physical phone and before using paid mobile data.
- **Research:** Android's [TV accessibility guidance](https://developer.android.com/training/tv/accessibility) calls for usable labels, TalkBack support and layouts that accommodate text scaling. Reuse existing tests and the device scenarios in `CLAUDE.md`.

## Next priority

### 5. Keep external subtitles with offline downloads

- **Gap:** `StreamDownload` stores playback identity/artwork but no subtitle-file metadata. Embedded tracks can remain in a downloaded video; externally fetched subtitle files are not explicitly retained for offline use.
- **Benefit:** Downloaded content remains accessible without needing a subtitle server connection.
- **Complete when:** Users can keep a selected external subtitle with a download and play it in airplane mode after restart. Store subtitle metadata/local paths, handle failed subtitle downloads visibly, and remove associated files when the video is deleted. Preserve subtitle-host header isolation; never forward a video provider's credentials to another host.
- **Research:** [Plex Downloads FAQ](https://support.plex.tv/articles/downloads-sync-faq/) describes offline subtitle behavior. Extend Flick's existing download records/player rather than adding another download system.

### 6. Add consistent download network and storage controls

- **Gap:** Downloads already have progress, pause/resume, retry, deletion and persistence. `enqueueStream` does not set a user-controlled Wi-Fi restriction, and no app-level free-space overview/preflight was found.
- **Benefit:** Avoid unexpected mobile-data use and downloads failing late because storage is full.
- **Complete when:** A persisted Wi-Fi-only choice is honored by HTTP and native torrent downloads, including restart and network changes. Explain when a download is waiting for the allowed network. Show downloaded-file storage usage/free space; warn about known insufficient capacity and handle unknown sizes/disk-full errors. Let users select files for cleanup without deleting anything automatically.
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

## Scope notes

Favourites/watchlist, movie/series filtering, basic subtitle/audio selection, Up Next/autoplay, buffering feedback/source-switch guidance, download pause/resume/retry and picture-in-picture already exist and are intentionally absent as new-feature suggestions. The items above describe specific remaining gaps. Do not reintroduce removed accounts or Jellyfin based on obsolete handoff entries.
