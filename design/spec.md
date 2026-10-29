# Spec: Discover (delta on Afterglow)

Direction: Afterglow (REVAMP_PLAN.md), unchanged tokens unless listed under "New tokens". Brief: design/brief.md.

## Data contract (Stremio addon protocol)

`lib/addons.dart`, no new packages (`http`, `shared_preferences` already installed).

| Call | URL | Returns |
|---|---|---|
| manifest | `{base}/manifest.json` | `{id, name, version, resources, types, catalogs, idPrefixes?}` |
| catalog | `{base}/catalog/{type}/{id}.json`, `.../{id}/search={q}.json`, `.../{id}/skip={n}.json` | `{metas: [{id, type, name, poster?, releaseInfo?}]}` |
| meta | `{base}/meta/{type}/{id}.json` | `{meta: {id, type, name, poster?, background?, logo?, description?, releaseInfo?, runtime?, imdbRating?, genres?, videos?: [{id, title/name, season, episode, released, thumbnail?}]}}` |
| stream | `{base}/stream/{type}/{videoId}.json` | `{streams: [{name?, title?/description?, infoHash?, fileIdx?, url?, sources?, behaviorHints?: {filename?, videoSize?}}]}` |

- `base` = manifest URL minus `/manifest.json`. Input accepts `stremio://` (→ `https://`), a base URL, or a manifest URL.
- `resources` entries are either a string or `{name, types, idPrefixes}`. An addon serves resource R for (type, id) when R is listed and the type and id prefix match the entry's own lists, falling back to the manifest's top-level `types`/`idPrefixes`.
- Catalogs shown in Discover: every installed addon's catalog of type movie/series with no required extra (`extra[].isRequired` false or absent, and not the legacy `extraRequired`).
- Meta: first addon serving `meta` for (type, id); Cinemeta for `tt…` ids.
- Streams: every addon serving `stream` for (type, videoId), queried in parallel, each with its own 15 s timeout, results grouped by addon.
- `infoHash` stream → `magnet:?xt=urn:btih:{hash}&dn={filename or name}` + `&tr=` for each `sources` entry starting `tracker:`. `fileIdx` is passed to the torrent screen. `url` stream → player directly. `externalUrl` stream (WatchHub) → opens outside Flick (Android `ACTION_VIEW` via the `flick/torrent` channel). `ytId` streams are dropped.
- Subtitles: `{base}/subtitles/{type}/{videoId}.json` → `{subtitles: [{id, url, lang}]}` from every addon serving `subtitles`; passed to the player as media_kit `SubtitleTrack.uri`.
- Bundled addons are manifest snapshots in `lib/addons.dart`; Cinemeta is locked on, the other bundled ones have an on/off switch (state persisted). User-added manifest URLs + cached manifests are persisted in shared_preferences.
- Stream text parsing (display only): quality from `\b(2160p|4k|1080p|720p|480p|360p)\b` over name+title (2160p→4K); none → `Unknown`, never SD; seeders after 👤 (absent = unknown, shown "—", distinct from 0); size after 💾 or `\d+(\.\d+)? (GB|MB)`; origin after ⚙️. Emoji are removed from displayed text.

## Torrent screen delta

`TorrentScreen(magnet, {fileIdx, title})`: when metadata arrives and `fileIdx` names a **playable video** file, it opens that file once per attempt (the "Choose a video" stage reads "Opening {file}"). A missing, unknown or non-video index falls back to the existing video list. When the auto-opened player closes, Torrent start pops itself so the user lands on the unchanged stream list (scroll, filter and rows kept). The player header uses `title` when given.

## Source changes and false empties

Manifests are cached with their URLs in shared_preferences and loaded before `runApp`, so the installed list is known on the first frame: "No stream sources installed" can never flash while loading. Title/Streams listen to `addons`; adding or removing a source re-queries only the affected group, keeps the other groups, and drops responses that arrive for a source list that has since changed.

## Files

| File | Holds |
|---|---|
| `lib/addons.dart` | protocol client, models (records), parsing, persistence (`Addons` ChangeNotifier) |
| `lib/state.dart` | `final addons = Addons();` |
| `lib/screens/discover.dart` | D1 |
| `lib/screens/title.dart` | D2, D3, shared stream list |
| `lib/screens/sources.dart` | D4 |
| `lib/screens/torrent.dart` | fileIdx + title |
| `lib/main.dart` | Discover tab, `addons.load()` |
| `test/addons_test.dart` | protocol + parsing + magnet, using the attached torrent's hash (`ED0AFBC1…321D`, Rick and Morty S04E02) |

## Visual layer

Codex's full geometry, styles and states: `design/codex-visual.md` (recommended variants: poster wall, quality-column row). Mockups: `design/mockups/`. Overrides from the UX review (`design/decisions.md`):

- **D1 header (exact):** search field + profile avatar y24–80 (12dp gap, 48dp targets); Movies/Series switch y88–136; catalog chips y144–192 (scroll horizontally when they overflow, never clip); grid from y200. The saving comes from consolidating the header into one row. Discover draws its own header, so the shell shows no AppBar on this tab (as on Home).
- **Shell nav:** unchanged theme; Discover is the 2nd destination (`explore_outlined`/`explore`).
- **Stream row:** no chevron; telemetry separated by " · ".
- **No profile-sheet entry** for Sources.

## Motion and transitions

| From → to | Transition | Tokens |
|---|---|---|
| Discover poster → Title | `Hero` on poster art (tag = meta id), title poster 80×120 | route duration `sheetDuration` 280 ms, `curveIn` |
| Title → Streams, Title/Streams → Sources, → Torrent start | existing MaterialPageRoute transition | theme default |
| press: poster, episode row, stream row | scale 0.97 | `stateDuration` 120 ms, `curveIn` |
| chip / season / segment change | selection haptic, content swap without animation | `stateDuration` |
| stream tap | light impact haptic | — |
| artwork | fade in | `artworkFadeDuration` 180 ms (NetImage) |
| removed source row → Undo row | cross-fade | `artworkFadeDuration` |

Reduced motion (`MediaQuery.disableAnimations` / platform `disableAnimations`): new routes use zero-duration transitions, no Hero travel, no press scale; source removal ↔ Undo swaps instantly. Skeletons are static already (no shimmer).

## Accessibility

- Movies/Series segment and every chip expose selected state; season chips the same.
- Back, Sources, profile, remove, Undo and search-clear have spoken labels.
- A stream row is one semantics node: "{quality}, {release}, {n} seeders, {size}, from {origin}"; a missing value is omitted from speech, not read as zero.
- Future episodes: disabled semantics with "Airs {date}".
- Inline errors, "{Source} removed, Undo" and per-source failures are announced (live region) without moving focus.
- Text scale: rows and telemetry wrap and grow; chips scroll; nothing clips at 1.3×.
