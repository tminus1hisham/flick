# Brief: Discover (Stremio-style titles → streams)

Owner: Claude (senior UX). Visual layer: Codex, inside the approved Afterglow direction (REVAMP_PLAN.md).

## Job

"I want to watch X tonight. Show me what exists, let me pick a title (or an episode), show me every torrent available for it, and let me pick one and play."

Stremio's model, copied on purpose:
- **Addons** supply everything over HTTP: `manifest.json`, `/catalog/{type}/{id}[/{extra}].json`, `/meta/{type}/{id}.json`, `/stream/{type}/{videoId}.json`.
- **Cinemeta** (`https://v3-cinemeta.strem.io`, Stremio's official metadata addon) is built in: Popular / New / Featured for movies and series, search, title metadata and full episode lists.
- **Bundled:** Stremio's official addon set (decisions.md, "Bundled addons"): Cinemeta, Public Domain Movies, WatchHub, OpenSubtitles v3. Third-party stream sources are added by pasting a manifest URL, as in Stremio.
- A stream with `infoHash` (+ `fileIdx`, `sources`) becomes a magnet for the existing libtorrent engine. A stream with `url` plays directly.

Users: one person, on a phone, in the evening, often on flaky Wi-Fi. Already signed in to Jellyfin (Discover lives in the signed-in shell).

## Screen inventory

| # | Screen | New/changed | Scroll |
|---|---|---|---|
| D1 | **Discover** (new tab) | new | **allowed** (poster grid, paged) |
| D2 | **Title** (movie or series) | new | **allowed** (episode list / stream list) |
| D3 | **Streams** (one episode) | new | **allowed** (stream list) |
| D4 | **Sources** (installed addons) | new | allowed (list), must fit 360×640 with ≤4 addons |
| T | **Torrent start** (existing TorrentScreen) | changed: takes a chosen `fileIdx` and title | no |

A movie's streams sit on its Title page (no extra hop). A series needs one more level, so an episode opens D3.

## Flow map

```
Shell tabs: Home · Discover · Browse · Search · Downloads
Discover ──tap poster (Hero)──▶ Title
  Title (movie)  ──tap stream──▶ Torrent start ──metadata──▶ Player
  Title (series) ──tap episode──▶ Streams ──tap stream──▶ Torrent start ──▶ Player
  Streams/Title "No sources" ──Add a source──▶ Sources
Profile sheet ──Sources──▶ Sources
url stream ──▶ Player directly
```

Back always returns one level. Player close → Torrent start pops itself → user is back on the stream list, the list unchanged, so a dead torrent costs one tap to try the next.

## State matrix

| Screen | Loading | Empty | Error | Offline | Success |
|---|---|---|---|---|---|
| D1 Discover | skeleton poster grid (real cell size) | search: "Nothing found for “x”" + clear | friendly sentence + Try again; next-page failure = inline row at grid end with Retry, grid kept | same as error, "You're offline" copy | grid, pages in on scroll (skip=n) |
| D2 Title | hero skeleton + 3 row skeletons | series with no episodes: "No episodes listed yet" | Try again | same as error | hero, meta, seasons/episodes or streams |
| D2/D3 streams block | one skeleton group per source asked, each resolves independently | **no stream source installed**: why + "Add a source" → D4; **sources answered, nothing found**: "No streams for this {movie, episode}" + which sources were asked | per source: "{Source} didn't answer · Retry", others still shown | per source error | grouped rows; filter chips when ≥2 sources |
| D4 Sources | — (local) | Cinemeta always listed, so never empty | add: inline field error ("That isn't a Stremio addon link", "Couldn't reach it", "Already added") | add fails with offline copy | list, add field, remove with inline Undo row |
| T Torrent start | existing stage spine; "Choose a video" stage skipped when fileIdx is known | fileIdx missing/not a video → falls back to the existing file list | existing | existing | auto-plays the chosen file |

## Interaction notes

- **D1 controls:** a Movies / Series switch and catalog chips (Popular, New, Featured, plus catalogs from installed addons with no required extra). Search is a field in the header; results replace the grid; clearing restores the catalog and its scroll position. One primary action: tap a poster.
- **Poster → Title:** Flutter `Hero` on the poster art, so the title page grows out of the tapped poster (spatial continuity). Everything else uses the app's existing page transition.
- **Stream row** carries, in this order of importance: quality (4K / 1080p / 720p / SD, parsed from name+title), release name (≤2 lines), seeders, size (mono), origin site. Addons pack this in free text with emoji (👤 💾 ⚙️). We parse them into real icons and strip the emoji; unparseable text is shown as plain lines. Sort order is the addon's own (addons already rank by quality and seeders).
- **Quality is the scan key.** Users scan for "1080p, lots of seeders, reasonable size". Quality sits left as a fixed-width tag so it forms a column; seeders tinted by health (≥20 success, 1–19 neutral, 0 warning, always with the number).
- **Episodes:** season chips; rows with a 16:9 still, "E2 · The Old Man and the Seat", air date. Future episodes show "Airs 12 Nov" and are not tappable.
- **Tap feedback:** rows and posters scale 0.97 on press (state duration), commit on release. Selection haptic on chip/season change; light impact on stream tap.
- **No new popups:** adding a source is an inline field on D4, not a dialog. Undo for remove is an inline row, not a snackbar.

## Allowed to scroll

D1, D2, D3, D4 (list). Torrent start must fit 360×640.

Viewport exception: the player is landscape-only, so its overlays (buffering panel, tracks panel) are checked against **640×360 dp** at 1.3× text instead of 360×640 (design/buffering.md).

## Out of scope (say so, don't build)

Library/watch history sync, YouTube and Local Files addons, trailers, addon catalogue browsing (`addon_catalog`), deep links (`stremio://` intents), offline Discover.

## Applied

- **ui-ux-pro-max:** chip collections wrap or scroll without clipping labels (Chip Collection Reflow); chips are real buttons with selected state (Compact Control Semantics); stable skeletons that reserve the real layout, no spinner (Loading Indicators, Content Jumping); lazy builder grids/lists (Flutter: ListView.builder); Hero for shared element (Flutter: Use Hero).
- **apple-design:** feedback on press, not release (§1 Response); Hero growth from the tapped poster, back returns along the same path (§7 Spatial consistency); specific labels ("Sources", not "Settings") and every screen answers where am I / how do I get out (§16 Wayfinding); reversible remove with undo, no confirm dialog (§16 Agency); haptics only on commit and selection (§13 Utility).
- **emil-design-eng:** stream rows and posters are seen tens of times per session, so motion is press-scale only, ≤160 ms, no stagger on every load (Animation decision framework, frequency); ease-out on entry (easing); stagger only on the first grid reveal, 30–50 ms, never blocking taps (Stagger).
