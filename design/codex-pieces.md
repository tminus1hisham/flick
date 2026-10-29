**Keep the 60dp alignment rail, give external services their own group, and use a custom player side panel for subtitles.** Sources fits five addons by removing the intro paragraph and using compact, flat rows.

All geometry below is at baseline text scale. Portrait screens include 24dp top and bottom system insets; the landscape Player is immersive. Generated mockups are visual references; the measurements govern implementation.

**Shared Afterglow rules**

Use `FlickTokens.background`, `surface1`, `surface2`, `outline`, `textPrimary`, `textSecondary`, `accent` and `onAccent`. Retain `artworkRadius` **8**, `controlRadius` **12**, `modalRadius` **24**, and `minTouchTarget` **48dp**.

No additional global tokens are needed beyond the approved `streamQualityWidth` **60dp** and `streamMonoStyle`. Use `FlickText` styles named below.

With reduced motion: transitions, scaling, cross-fades and artwork fades become immediate. Content reflows at larger text sizes; scrolling absorbs the extra height.

**1. WatchHub — external-service rows**

**Placement:** torrent groups first, followed by **Where to watch**, with supporting copy **“WatchHub · Opens another app or website.”** Keep addon order within each group. The WatchHub filter jumps directly to its offers, avoiding a long torrent list.

Use the same component on D2 movies and D3 episodes. A successful WatchHub response must not imply torrents were found.

| Element | Geometry at 360×640 | Style |
|---|---|---|
| Existing D3 header/context/filters | Through y192 | Existing approved layout |
| Torrent source heading | x20, y200, height 22 | `FlickText.cardTitle` |
| Two example torrent rows | y228–348; 60dp each | Existing shared stream row |
| Where to watch heading | x20, y364 | `cardTitle` |
| External-action explanation | x20, y390 | `metadata`, secondary |
| Service rows | y416–480 and y480–544; 320×64 | Flat background, 1dp dividers |
| Left alignment rail | x20–80, **60dp** | External-link icon; no quality label |
| Icon tile | 44×44, centred within rail | `surface1`, radius 12; 20dp `open_in_new` icon |
| Service name | x88, width 252 | `cardTitle`: “Rakuten TV” |
| Offer description | Under service name | `metadata`: “Rent · Buy” |
| Supporting note | x20, y564 | `metadata`, secondary |

No service logos, torrent health colours, seeders, sizes, play icons or trailing chevrons. The external icon, group heading and explanation jointly distinguish these rows from torrents.

On D2, this module follows the inline torrent groups in the same scroll view. When there are no torrent results, the service group moves up naturally.

**Interaction and motion**

- Whole row is the target; 0.97 press scale over `stateDuration` **120ms**.
- Launch the service on release through the existing Android channel; no confirmation popup.
- Returning to Flick preserves the title/episode, source filter and scroll position.
- A slow torrent source must not block resolved WatchHub offers.

**States**

- **Loading:** heading plus two 64dp skeleton rows, reserving the icon rail and both text lines.
- **No offers:** external-link icon, “No services listed for this title”, **Retry**.
- **Provider error/offline:** icon, “WatchHub didn’t answer” / “You’re offline”, **Retry**; retain torrent results.
- **Launch failure:** expand only that service row with an error icon, “Couldn’t open Rakuten TV”, **Try again**.
- **No applicable torrent provider:** retain a compact torrent callout with **Add a source**. WatchHub and OpenSubtitles do not count as torrent providers.

**Accessibility:** one link node per row: “Rakuten TV, rent or buy. Opens another app or website.” Announce launch failure without moving focus. Preserve the service’s full offer text when it wraps.

**2. Player — subtitles side panel**

Use a **custom overlay attached to Player**, independent of media_kit’s auto-hiding controls. It occupies the right half of the landscape screen and leaves the video visible at full size beneath it.

**Top-bar entry, panel closed**

| Element | Geometry at 640×360 | Style |
|---|---|---|
| Existing top bar | y0–64 | Existing scrim |
| Back | x4, 48×48 | Existing control |
| Title, episode, buffer | Flexible area from x60 | Existing `titleSmall`, `labelMedium`, `monoStyle` |
| Subtitles control | x536, y8, 96×48 | Caption icon + “Subtitles”; `FlickText.button` |
| Optional quality control | Immediately before Subtitles | Existing behaviour retained |

Allow the title block to truncate before either control loses its touch target. Route any existing subtitle shortcut to this panel so there is only one subtitle chooser.

**Panel open**

| Element | Geometry | Style |
|---|---|---|
| Panel | x320, y0, **320×360** | Opaque `surface1`; left corners `modalRadius` 24, right corners square |
| Exposed-video scrim | x0–320 | Existing `modalBarrier`, 56% black |
| Heading | x340, y16 | `railHeading`: “Subtitles” |
| Provider | x340, y44 | `metadata`: “OpenSubtitles v3” |
| Close | x584, y8, 48×48 | Existing icon button |
| Off row | y72–120 | `body`, radio selection |
| Language row | y120–168 | `metadata` label; `button` language name |
| File count | x340, y180 | `metadata`: “English · 90 files” |
| File list | y204–360, independently scrollable | 72dp minimum rows |
| File selection marker | 3dp leading strip plus check | `activeMarker`, selection also expressed by icon |
| Filename | Up to two lines | `body` |
| Supporting line | Beneath filename | `metadata`, secondary |

Example filenames are `Rick.and.Morty.S04E02.1080p.WEB-DL.x265` and `…720p.WEBRip.x264`. Show supplied filenames; if absent, use neutral labels such as **“English · File 2”**, without inventing release quality.

**Language selection stays inside this panel.** Tapping Language replaces its contents with:

- Header **Languages**, an internal Back target and Close.
- A 52dp search field.
- Scrollable 48dp language rows: **English · 90 files**, **Spanish · 24 files**.
- Human-readable language names; map codes such as `eng` and `spa` to labels.

Selecting a language returns to its file list. Preserve file-list scroll position separately for each language.

**Selection behaviour**

- At playback start, match the device language to the available language codes and try the first matching entry in addon order.
- If that language is absent, remain **Off** and explain why; do not silently substitute another language.
- Manual language/file selection or Off wins over late automatic responses.
- Keep the previous subtitle active until a replacement loads successfully. Mark a new file selected only after application succeeds.
- Keep the panel open while comparing files. Playback continues; opening or closing the panel does not seek or restart video.

**Motion**

- Slide panel from the right over `sheetDuration` **280ms**, using `curveIn`; exit uses `curveOut`.
- Fade the exposed-video scrim over `artworkFadeDuration` **180ms**.
- Language-view changes and selection feedback use `stateDuration` **120ms**.
- Selection haptic on successful manual language/file/Off changes; none for automatic selection.
- Android Back closes the language subview first, then the panel, then follows normal Player navigation.

**States**

| State | Presentation |
|---|---|
| Loading catalogue | Keep Off accessible; static 72dp file skeletons |
| Device language unavailable | Language icon, “No French subtitles found”, **Choose language** |
| No subtitles at all | Caption icon, “No subtitles found for this episode”, **Retry** |
| Fetch error/offline | Error icon, specific sentence, **Retry**; video continues |
| Applying a file | Pending row reads “Opening subtitles…”; current selection remains checked |
| File failed | Inline error, “Couldn’t load this subtitle file”, **Retry**; keep previous track |
| Provider disabled | Caption icon, “OpenSubtitles is off”, **Enable OpenSubtitles** |
| Language search empty | Search icon, “No matching languages”, **Clear search** |

Subtitle errors stay in the panel; they must not use the existing Player snackbar error handler.

**Accessibility:** treat the panel as a modal focus scope, excluding underlying controls. Focus its heading on entry and return focus to Subtitles on close. Outside tap closes without activating transport controls. Announce pending/error/selected changes without moving focus. File rows use radio semantics; the top-bar control announces the active language or Off.

**Integration requirement:** Player needs the canonical Stremio video ID; the existing generic torrent item ID alone cannot identify the episode for subtitle lookup.

**3. D4 Sources — bundled and user-added**

Remove the introductory sentence. Use two labelled, flat sections, with the add form immediately beneath them.

| Element | Geometry at 360×640 | Style |
|---|---|---|
| Masthead | y24–72 | Back 48dp; `pageTitle` |
| Bundled label | x20, y80 | `smallLabel`, secondary |
| Four bundled rows | y100–356; **64dp each** | Flat, 1dp dividers |
| Name | x20, width 260 | `cardTitle` |
| Capability / Built-in label | Under name | `metadata`, secondary |
| Lock / switch area | x292, 48×48 | Vertically centred |
| User-added label | x20, y364 | `smallLabel` |
| One user row | y384–448 | Same typography; remove target 48×48 |
| Add a source label | x20, y460 | `button`; external field label |
| Manifest input | x20, y484, 320×52 | Existing input theme, radius 12 |
| Helper/error slot | x20, y540, height 16 | `metadata` |
| Add source button | x20, y564, 320×48 | Existing filled button theme |
| Gesture inset | y616–640 | Background |

| Addon | Supporting text | Trailing control |
|---|---|---|
| Cinemeta | Built-in · Catalogs · Title details | Non-interactive lock |
| Public Domain Movies | Built-in · Catalogs · Torrents | On/off switch |
| WatchHub | Built-in · Where to watch | On/off switch |
| OpenSubtitles v3 | Built-in · Subtitles | On/off switch |
| Northstar — example user addon | Streams · Movies & series | Remove |

Switch visual: **40×24dp inside a 48×48 target**, stadium shape. On uses `accent` with `onAccent` thumb; off uses `surface2`, `outline` and a `textSecondary` thumb. This needs no new colour token or global theme change.

**Motion and behaviour**

- Switch changes use 120ms plus selection haptic; their rows stay in place.
- Toggling updates affected catalogs/results without refreshing unrelated groups or interrupting active playback.
- User removal cross-fades to a same-height **“Northstar removed” + Undo** row over 180ms. Undo remains available while on Sources.
- Built-in addons are never removable. Cinemeta cannot be disabled.

**States**

- Bundled snapshots and persisted settings appear immediately, without remote loading placeholders.
- With no user addons, use a link icon and “No user-added sources”; retain the add form and its single action.
- While adding, button reads **“Checking link…”**; retain its dimensions.
- Invalid/unreachable/duplicate/offline errors replace the reserved helper line with icon + sentence; **Add source** remains the retry action.
- If saving a toggle fails, restore its previous state and show an inline error with **Retry**. Error expansion may scroll; normal five-addon layout fits.
- Keyboard and enlarged text scroll the form into view without shrinking controls.

**Accessibility:** switches announce addon name and on/off state, with capabilities as supporting semantics. Cinemeta announces “Built-in, always enabled”; the lock is decorative. Remove labels include the addon name. Announce removal/Undo and validation errors without stealing focus.

**Rendered image paths**

| Mockup | Absolute path |
|---|---|
| WatchHub alongside torrents | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-d53fe5e7-90cd-4089-bdb7-f2dc350e594d.png` |
| Landscape subtitle panel | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-102c8224-f4f4-41c5-92cb-29a7672bbc2a.png` |
| Sources with five addons | `C:\Users\PC\.codex\generated_images\01a1870f-04fa-7813-8713-cbba3618bd6c\exec-ae7b2458-5764-42f0-a511-44a2578cd1d4.png` |

Skipped: implementation and device validation; no shell commands ran.  
Risk: generated geometry is approximate; subtitle language matching, file application and external-app return behaviour need validation during implementation.
---

## UX overrides (Claude, senior UX)

- **Subtitles panel: no scrim on the exposed video.** The panel stays open while comparing files so the viewer can see each subtitle render; a 56% dim hides exactly that. Non-blocking panel → separate, don't dim (apple-design §12). Keep the modal focus scope; an outside tap still closes the panel without reaching transport controls.
- **Subtitle file rows:** the supporting line shows what distinguishes files (release format/group, fps), not the provider name repeated on every row; the provider is already under the heading.
