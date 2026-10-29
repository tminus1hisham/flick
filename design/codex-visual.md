**Recommended: a compact poster grid for Discover, paired with flat stream rows whose fixed quality column anchors comparison.** Artwork provides the atmosphere; typography and alignment make choosing a stream quick.

The five final mockups are rendered. Measurements below are the implementation specification; generated images are visual references. Northstar, Open Reel and Atlas Catalog are fictional addons, and torrent statistics are illustrative.

**1. Layout variants**

| Component | Variant | Rationale |
|---|---|---|
| D1 Discover | **A — Poster wall, recommended:** three equal columns, title captions, compact controls above. | Shows more choices immediately and preserves a predictable position when returning from a title. |
| D1 Discover | B — Editorial index: vertically stacked rows, each with a 72×108 poster, larger title, genre and short description. | Helps unfamiliar-title discovery, but shows fewer titles and requires more scrolling. |
| Stream row | **A — Quality column, recommended:** fixed quality tag left; release name and telemetry right. | Quality, seeders and size form repeatable scan positions across sources. |
| Stream row | B — Quality spine: fixed left tag; release name beside it; seeders and size stacked in a right-hand column, origin underneath. | Prioritises numerical comparison, but leaves less room for release names on narrow phones. |

Both stream variants retain source grouping and addon order. Neither introduces quality sorting, recommendations or a separate play button.

**2. Shared visual specification**

Coordinates use a **360×640dp viewport**, including a 24dp status inset and 24dp bottom gesture inset. Content gutters are `FlickTokens.pageGutter` = **20dp**, giving **320dp usable width**.

| Element | Existing theme mapping |
|---|---|
| Canvas | `FlickTokens.background` — `#080808` |
| Subtle surfaces / fields | `surface1` / `surface2` — `#141414` / `#242424` |
| Dividers / control outlines | `outline` — `#454545`, 1dp |
| Primary / supporting copy | `textPrimary` / `textSecondary` |
| Selected chips | `accent` background, `onAccent` label; existing `chipTheme` |
| Artwork / controls | `artworkRadius` **8dp** / `controlRadius` **12dp** |
| Existing profile sheet | `modalRadius` **24dp**; no new sheets |
| Controls | `minTouchTarget` **48dp** |
| Screen / title / section headings | `FlickText.pageTitle`, `detailTitle`, `railHeading` |
| Release names / descriptions | `FlickText.body` |
| Captions / dates / origins | `FlickText.metadata` |
| Control labels | `FlickText.button`; chips retain the existing plain `metadata` label style |
| Hero readability | Both `context.flick.scrimTop` and `scrimBottom`, across the full artwork bounds |

Only two additions are needed:

| New token/style | Value | Why |
|---|---|---|
| `FlickTokens.streamQualityWidth` | **60dp** | Keeps quality aligned across movie and episode streams. |
| `streamMonoStyle` | `monoStyle.copyWith(fontSize: 12, height: 16 / 12)` | Fits seeders and size alongside origin without shrinking the whole row. Retains Roboto Mono 500 and tabular figures. |

Other dimensions below are component geometry, not new global theme tokens. No new colours, fonts or duration tokens.

At larger text sizes, rows grow and chip collections scroll or wrap without clipping. The fixed coordinates describe the baseline text scale.

**3. D1 Discover**

| Element | Geometry | Style |
|---|---|---|
| Masthead | y24–72; title x20; profile target x292, 48×48 | `pageTitle`; existing profile control |
| Search | x20, y80, 320×52 | Existing input theme; `body`; search and clear targets 48dp |
| Movies / Series switch | x20, y144, 320×48 | `button`; selected segment `surface2`, 3dp `activeMarker` underline |
| Catalog chips | y204, 48dp touch band; 8dp gaps | Existing chip theme; Popular selected |
| Poster grid | x20, y264; three columns; 12dp gaps | Artwork **98.7×148dp**, radius 8 |
| Poster captions | 8dp below art; reserve two lines, 32dp | `metadata`, primary colour |
| Grid cell | 188dp high; 12dp vertical gap | Flat artwork and caption; no enclosing card |
| Shell navigation | y536–616, 80dp high; five 72dp destinations | `surface1`; 22dp icons, `metadata` labels |
| Gesture inset | y616–640 | Background |

Navigation keeps Home · Discover · Browse · Search · Downloads. Discover uses a red icon and short 3dp marker above it, with a white label. Remove the default selected pill locally.

The grid shows Rick and Morty, Severance, Dark, The Bear, Silo and Arcane with original abstract artwork. No feature banner, carousel or oversized heading.

**Motion:** posters scale to **0.97** on pointer-down over `stateDuration` **120ms**, restoring or committing on release. Artwork fades over `artworkFadeDuration` **180ms**. Segment and catalog selection use 120ms plus selection haptic on commit. No repeated grid stagger.

**States:**

- **Loading:** exact 98.7×148 artwork skeletons plus two caption bars; preserve the 188dp cells.
- **Empty search:** left-aligned search icon, “Nothing found for ‘x’”, **Clear search**. Clearing restores the catalog and its scroll position.
- **Error / offline:** icon, “Couldn’t load these titles” or “You’re offline”, **Try again**, starting in the grid area.
- **Pagination error:** keep every loaded poster; append a full-width inline icon, sentence and **Retry** row.
- Search results replace the grid while retaining the header and shell navigation.

**4. Shared stream row**

The same component appears in D2 movies and D3 episodes.

| Part | Geometry | Style |
|---|---|---|
| Whole row | 320dp wide; **60dp minimum height** | Flat background; 1dp bottom divider |
| Quality column | x20–80; tag 60×24, vertically centred | `metadata` with weight 700; `surface2`; 12dp radius |
| Content | x88–340, 252dp wide; 12dp vertical padding | No trailing menu or separate play button |
| Release | 20dp line; up to two lines | `body`, primary |
| Telemetry | 16dp line immediately below | Seeder icon + number, size, origin |
| Numbers | Seeders and size | `streamMonoStyle` |
| Origin | After size | `metadata`, secondary |

One release line produces a 60dp row; two lines produce **80dp**. If telemetry needs another line, the row grows again rather than clipping information.

Seeders use `context.flick.success` for **≥20**, secondary text for **1–19**, and `warning` for **0**. The number and icon remain visible in every state. Missing values display **—**, never an invented zero. Unparsed addon text remains readable as plain lines; emoji metadata becomes real icons.

**Interaction:** 0.97 press scale over 120ms; light impact on committed stream tap. No persistent selection after returning from playback. Preserve source filter, scroll position and rows unchanged.

**5. D2 Title — series**

| Element | Geometry | Style |
|---|---|---|
| Abstract backdrop | x0, y24–252, full width | Existing hero scrims |
| Back / Sources | y28; back 48dp; Sources 76×48 at right | Existing icon/text button styling; Sources explicitly labelled |
| Hero poster | x20, y104, 80×120 | Radius 8; shared `Hero` |
| Title | x116, y128, width 224; up to two lines | `detailTitle` |
| Year / type | Below title | `metadata`, secondary |
| Genres | x20, y236, 320×16 | `metadata`, secondary |
| Synopsis | x20, y260, 320×40 | `body`, two-line preview |
| Episodes heading | x20, y312, height 26 | `railHeading` |
| Season chips | y346–394; horizontal collection | Existing chip theme; **S4 selected** |
| Episode rows | Start y406; **88dp minimum** | Flat divided rows |
| Episode still | x20, 96×54, centred vertically | 16:9; radius 8 |
| Episode copy | x128, width 212 | `body`, up to two lines; date `metadata` |

The first two complete episode rows are visible; the third continues below. Future episodes show **“Airs 12 Nov”**, have no tap action and expose their unavailable state to accessibility services.

**Motion:** the poster follows the shared Hero route forward and backward; use `sheetDuration` **280ms** where that route’s duration is configured. Existing page transition behaviour remains otherwise. Artwork fades over 180ms. Episode presses and season changes use 120ms; season commits receive selection haptics.

**States:**

- **Loading:** backdrop, 80×120 poster, title bars and three 88dp episode skeletons.
- **No episodes:** retain title metadata and seasons; episode icon, “No episodes listed yet”, **Refresh**.
- **Title error / offline:** keep Back available; icon, specific sentence, **Try again**.
- Failed artwork uses the existing image fallback without blocking episode access.

**6. D2 Title — movie**

Arrival uses the same compact title composition, with streams directly below it.

| Element | Geometry | Style |
|---|---|---|
| Abstract backdrop | y24–224 | Existing scrims |
| Back / Sources | Same as series | Existing controls |
| Poster | x20, y92, 80×120 | Radius 8; shared Hero |
| Title / year / runtime | x116, starting y120 | `detailTitle`; `metadata` |
| Genres | x20, y232 | `metadata` |
| Synopsis | x20, y256, 320×40 | `body` |
| Streams heading | x20, y312 | `railHeading` |
| Source filters | y344–392 | Existing chips; shown when ≥2 sources |
| First source heading | x20, y404, 24dp band | `smallLabel`, secondary |
| Stream rows | Start y428 | Shared component; 60–80dp or taller as required |

The first two stream choices fit before the bottom inset. There is no additional movie Streams route.

**Motion:** same Hero and artwork behaviour as series; shared stream press feedback. Source-filter selection takes 120ms with a selection haptic.

**States:** title loading/error mirrors series. Stream loading, empty and partial failures use the shared source states below.

**7. D3 Streams — S4E2**

| Element | Geometry | Style |
|---|---|---|
| Masthead | y24–80; Back, Streams, Sources | `pageTitle`; 48dp controls |
| Series / episode context | x20, y84, height 16 | `metadata`, secondary |
| Episode title | x20, y104, height 26 | `railHeading`; wraps and grows when necessary |
| Source filters | y144–192 | All selected; Northstar; Open Reel |
| Northstar heading | y200–220 | `smallLabel` |
| Three stream rows | y220–400, 60dp each | Shared component |
| Open Reel heading | y400–420 | `smallLabel` |
| Three stream rows | y420–600, 60dp each | Shared component |
| Bottom clearance | y600–616 | Background |

All six rows fit with single-line releases. Longer releases naturally extend the scrollable list.

| Source | Quality | Release | Seeders | Size | Origin |
|---|---|---|---:|---:|---|
| Northstar | 1080p | S04E02 WEB-DL x265 | 284 | 812 MB | 1337x |
| Northstar | 720p | S04E02 WEBRip x264 | 96 | 307 MB | The Pirate Bay |
| Northstar | 480p | S04E02 HDTV x264 | 12 | 156 MB | EZTV |
| Open Reel | 1080p | S04E02 WEB-DL x265 | 43 | 1.12 GB | TorrentGalaxy |
| Open Reel | 720p | S04E02 WEBRip x264 | 7 | 329 MB | 1337x |
| Open Reel | 480p | S04E02 HDTV x264 | 0 | 171 MB | The Pirate Bay |

**Motion:** existing route entry; filter feedback 120ms; stream press scale 120ms. Resolved source groups appear without row stagger or list-wide animation.

**Shared D2/D3 stream states:**

- **Loading:** one independently resolving group per requested source, with its heading and real row skeleton geometry.
- **No installed stream source:** extension icon, “Install a stream source to find playable links”, **Add a source** → D4.
- **Sources returned nothing:** video icon, “No streams for this episode” or “No streams for this movie”; supporting line naming the queried sources; **Refresh streams**.
- **Partial failure:** retain successful groups. Failed group shows warning icon, “Northstar didn’t answer”, **Retry**.
- **Offline:** failed group shows offline icon, “You’re offline”, **Retry**. Other resolved groups remain visible.

**8. D4 Sources**

A flat installed-addon ledger leads directly into the inline add form.

| Element | Geometry | Style |
|---|---|---|
| Masthead | y24–80 | Back 48dp; `pageTitle` |
| Intro | x20, y88, 320×20 | `body`: “Install addons to find streams.” |
| Installed label | x20, y124 | `smallLabel`, secondary |
| Four addon rows | x20, y148–404; 64dp each | Flat, divided; no enclosing cards |
| Addon icon | 32dp, vertically centred | Existing line-icon vocabulary |
| Name / capability | x64; name above capability | `cardTitle` / `metadata` |
| Remove target | x292, 48×48 | Existing icon button theme |
| Add heading | x20, y420 | `railHeading` |
| Manifest URL label | x20, y454 | `metadata`; external label |
| Input | x20, y478, 320×52 | Existing input theme |
| Helper / error slot | x20, y534, height 16 | `metadata` |
| Add source | x20, y558, 320×48 | Existing filled button |
| Gesture inset | y616–640 | Background |

Example installed rows: Cinemeta, Northstar, Open Reel and Atlas Catalog. Cinemeta carries a **Built-in** label and lock; it cannot be removed. Capabilities distinguish catalogs from stream providers.

**Motion:** press feedback uses 120ms. Removing replaces that same 64dp row with “Northstar removed” and **Undo**, preserving position. Keep Undo available while on D4. Successful additions fade into their row over 180ms.

**States:**

- **Initial load:** local data appears immediately.
- **No user stream sources:** Cinemeta remains; extension icon and “No stream sources installed” accompany the existing add form. Its **Add source** button is the single action.
- **Checking a link:** retain form geometry; button reads “Checking link…” with a 3dp linear indicator inside its bounds.
- **Invalid / unreachable / duplicate:** field error icon and respectively “That isn’t a Stremio addon link”, “Couldn’t reach it”, or “Already added” replace the reserved helper line.
- **Offline add:** “You’re offline” in the same slot; preserve the pasted URL. **Add source** remains the retry action.

Four rows and the form fit at baseline scale. With the keyboard or enlarged text, the form scrolls into view.

**Playback handoff**

Carry the selected title into Torrent start. With a valid `fileIdx`, skip “Choose a video”; otherwise retain the existing file fallback. Keep the labelled stage spine and `monoStyle` telemetry. Direct URL streams open Player. Closing playback returns to the unchanged stream list.

Reduced motion disables scale and Hero travel; no interaction waits for an animation.

**9. Image paths**

Final mockups:

| Screen | Absolute path |
|---|---|
| D1 Discover | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-a46c556c-305b-4f14-939c-0a055bc029f8.png` |
| D2 Series | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-78f7a99a-687e-4eae-adff-154318e8c3e9.png` |
| D3 Streams | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-370973bc-e69a-46c6-9af2-c92b65ef9775.png` |
| D2 Movie | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-1428c313-6471-4602-8ab2-3cc7a94c6f65.png` |
| D4 Sources | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-1a100cb2-9b8a-4710-9ce5-9972a1999628.png` |

Superseded initial renders, retained:

| Screen | Absolute path |
|---|---|
| D2 Series initial | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-93f210cb-a3f3-4370-9fbb-efde7fffcb52.png` |
| D3 Streams initial | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-33c43bed-83f0-4b13-816c-1d625eb5a300.png` |
| D2 Movie initial | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-b2ce53a4-ab81-421e-82d4-a579812f076a.png` |
| D4 Sources initial | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-0e9a9e71-aa65-4bdc-894d-21f023ca8445.png` |

Skipped: implementation, device checks, history sync, subtitle addons, trailers, addon browsing, deep links and offline Discover; no shell commands ran.  
Risk: generated typography and spacing can drift—including “WEBRip” in D3—so use the written measurements and content for implementation.