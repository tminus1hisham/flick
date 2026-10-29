# Decisions (ponytail gate + UX review of Codex's visual layer)

## Ponytail ultra, UX
- cut: Discover masthead "Discover" title → the search field is the header, profile avatar on its right. The tab label already says Discover; saves 56dp so ~2 poster rows show at 360×640 instead of ~1.5.
- cut: a separate Streams route for movies → streams inline on the movie's Title page.
- cut: per-stream detail screen → a tap plays.
- cut: addon catalogue browser (`addon_catalog`) → paste a manifest URL, as Stremio's "Add addon" field.
- cut: "Sources" entry in the profile sheet → the "Sources" button on Title/Streams and the "Add a source" empty state already reach it at the moment it is needed.
- cut: "Choose a video" stage when the stream names its file (fileIdx) → auto-play that file.
- kept: Discover as a 5th tab, because Browse is the Jellyfin library; mixing addon titles into it breaks "where am I". 5 is the bottom-nav limit.
- kept: inline Undo after removing a source, because removal is otherwise silent and irreversible without re-finding the URL (Agency).
- kept: catalogs from installed addons as extra chips, because it is a filter over manifests already fetched (a few lines).

## Ponytail full, code plan
- kept: 4 new files (addons.dart, discover.dart, title.dart, sources.dart); D2 and D3 share one stream list widget in title.dart.
- reuse: NetImage, Skeleton, friendlyError/ErrorState, monoStyle, scrims, chip/input/button themes, existing page transition.
- no new packages: `http` + `shared_preferences` cover the protocol and persistence.
- new tokens: only `FlickTokens.streamQualityWidth` (60) and `streamMonoStyle` (from Codex).

## Rejected from Codex's proposal
- Restyling the shell NavigationBar (marker above icon, no pill) for Discover: changes every tab's look, out of this feature's scope. Discover uses the existing themed bar.
- Trailing chevrons on stream rows (in the D3 render, not in Codex's written spec): the written spec wins, no trailing affordance; the whole row is the target.
- "|" separators in telemetry (D3 render): use the "·" of the movie render, matching the app's metadata lines.

## Accepted deviations from build-mobile hard rules (pre-existing app)
- The app has no `lib/kit/`, no presets and no theme changer; it went through the earlier UI revamp, not this pipeline. The new screens use no stock dialog, snackbar, picker or spinner at all, so no kit is needed for them. Kit + presets are a separate job.
- `gates.py` already fails on the existing files (theme in lib/theme.dart, Colors.* in older screens). Gate for this feature: zero hits in the new files.

## Bundled addons (user request 2026-10-29: "addons come full package")

Source: github.com/stremio/stremio-official-addons `index.json`. stremio-core's `Profile::default()` installs exactly this list (`addons: OFFICIAL_ADDONS`). Every endpoint probed live on 2026-10-29.

| Addon | Gives | Flick |
|---|---|---|
| Cinemeta | catalogs, title + episode metadata | **bundled**, locked on (as Stremio: `protected`) |
| Public Domain Movies | a movie catalog + torrent streams (`infoHash`, `fileIdx`) | **bundled**; also our legal end-to-end torrent test (The Kid, 1921, 1080p) |
| WatchHub | "where to watch" streams (`externalUrl`: Netflix, Rakuten, …) | **bundled**; rows open the service's app or site (Android intent via the existing Kotlin channel, no new package) |
| OpenSubtitles v3 | subtitles per video id | **bundled**; subtitles in the player (auto-pick device language, switch/off in a player panel) |
| OpenSubtitles (legacy v1) | old subtitles protocol | skip: superseded by v3 |
| YouTube | `channel` catalogs, `ytId` streams | skip: needs a YouTube extractor; media_kit can't play a ytId |
| Local Files | needs Stremio's desktop server on 127.0.0.1:11470 | skip: Flick's Downloads tab already plays local files |

Bundled addons ship as manifest snapshots in code, so they work on first launch with no fetch. Cinemeta is locked; the other bundled ones get an on/off switch on Sources (no remove/re-paste needed). User-pasted addons keep remove + Undo.

Not bundled: third-party torrent indexers (Torrentio and similar). None is part of the Stremio org; Stremio leaves them to the user, and Flick does the same via "Add a source".

## Optional sign-in / guest mode (2026-10-29, design/guest.md)

User decisions: comments left out (no backend); favourites + likes on Jellyfin for Jellyfin titles and on the device for Discover titles; first launch keeps Login with "Continue as guest".

- cut: comments → no store exists (Jellyfin and addons have none).
- cut: Home/Browse/Search for guests → hidden; guest shell is Discover + Downloads, no dead tabs.
- cut: lock badges on gated toggles → normal off state, gate on tap.
- cut: Favourites screen/tab → Discover "Favourites" chip + Home "Favourites" row.
- cut: dislike → like on/off only.
- kept: resume intent (the tapped action completes after sign-in), because re-tapping after a detour is the main soft-gate friction.
- kept: guest Downloads tab, because old downloads must stay playable.
- added: `lib/kit/sheet.dart` (`showFlickSheet`), the first kit piece: the gate and the guest profile sheet open through it, so new files have zero gates.py hits. Older sheets still call showModalBottomSheet directly.
- override of Codex (guest-visual.md): Detail toggles sit **below** Play/Download, not above. Play stays the primary action by the title (Netflix's Play, then My List order).
- override of Codex: the Title row is a small `_Saving` widget, not an inline ListenableBuilder, to keep `_hero` readable.
- ponytail: device favourites not keyed per account; Home's Favourites row refreshes on pull, not on return from Detail.
