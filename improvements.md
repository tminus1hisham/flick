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

### 1. Persist viewing progress and offer Continue Watching

- **Gap:** `lib/saved.dart` persists favourites and likes; `lib/state.dart` persists autoplay. No persisted viewing history was found. `PlayerScreen` keeps a position for same-session retry, which does not provide resume after reopening the app.
- **Benefit:** Return to an unfinished film or episode without finding it and scrubbing manually.
- **Complete when:** Movie/episode progress survives app restart; title pages offer Resume and Start Over; Continue Watching opens the correct episode; completed titles leave that row. Provide removal/clear-history controls. Use stable, provider-scoped identities for addon, anime and downloaded content rather than expiring stream URLs; re-resolve online sources. Exclude live broadcasts. Check restart, completion, source changes and offline playback.
- **Start with:** `lib/screens/player.dart`, `lib/playback.dart`, `lib/saved.dart`, title/discovery/anime/download entry points. mpv documents [resuming playback](https://mpv.io/manual/stable/#resuming-playback), but app-level identity and discovery still need to be handled by Flick.

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

### 8. Search all enabled searchable catalogs

- **Gap:** Discover picks `catalogs.where((c) => c.searchable).firstOrNull`, so only the first searchable catalog for the selected type receives a query. Movie/series filtering and separate anime search already exist.
- **Benefit:** Find titles supplied by another enabled catalog without assuming the first catalog contains everything.
- **Complete when:** Search queries reach all enabled searchable catalogs for the current type, with deduplication by canonical type/ID, bounded requests and independent failure handling. A slow/unreachable addon must not hide successful results. Ignore stale responses after the query/type changes and preserve phone/TV focus behavior. Keep anime's separate provider search unless a concrete need justifies combining it.
- **Evidence:** `lib/screens/discover.dart` and the catalog capability parsing in `lib/addons.dart`; this recommendation follows from the current implementation rather than competitor feature parity.

## Scope notes

Favourites/watchlist, movie/series filtering, basic subtitle/audio selection, Up Next/autoplay, buffering feedback/source-switch guidance, download pause/resume/retry and picture-in-picture already exist and are intentionally absent as new-feature suggestions. The items above describe specific remaining gaps. Do not reintroduce removed accounts or Jellyfin based on obsolete handoff entries.
