# Flick on TV: brief (build-mobile phase 1, delta)

Plan: `~/.claude/plans/come-up-with-a-snoopy-cocke.md`. Codex rounds: tv-codex.md, tv-codex2.md (scratch). Applies on top of design/brief.md and design/spec.md. Afterglow palette and Manrope stay.

## User and job
One person on a sofa, 3 m from a 1080p Android/Google TV, holding a 5-key remote (D-pad, Select, Back, Home; sometimes Play/Pause). They want to find something, pick a working stream and watch, without typing. They also still use Flick on the phone, and portrait phone must not change.

## Form factors
| Context | Detected by | Layout | Tokens | Focus ring |
|---|---|---|---|---|
| Phone portrait | width < 600 | today's UI, bottom NavigationBar | FlickTokens | only when a keyboard is used (`highlightMode` traditional) |
| Phone landscape / tablet | width ≥ 600, not TV | bottom bar; grids adapt by `maxCrossAxisExtent`; Title splits only when both panes fit | FlickTokens | same |
| TV | native `tv` (UiModeManager) | side rail, 960×540 dp canvas inside 48/27 safe insets | FlickTv | always while `highlightMode` is traditional (always on TV) |

## Screen inventory (TV)
1. **Rail** (shell): Discover, Anime, Downloads at the top; Sources (gear) at the bottom. 72 dp collapsed; expands to ~200 dp over the content (never shifts it) while it holds focus. Selected = red marker; focused = ring.
2. **Discover** (landing): heading, Movies/Series, catalog chips (incl. Favourites), 5-column poster grid 144×216, search entry. Steady background, no hero.
3. **Title**: movie = art + facts (264) | streams (480). Series = art + facts | seasons + episodes; Select on an episode swaps the right pane to that episode's streams; Back returns to the episode with focus restored.
4. **Torrent start**: stages + file list (existing), focusable rows.
5. **Player**: TV key map (below), tracks panel ~320 dp right, Up Next card bottom-right, buffering panel.
6. **Anime**: Kitsu catalogs only (same grid as Discover). No Miruro search on TV.
7. **Downloads**: list rows; Delete is a visible row action, not a hidden popup menu.
8. **Sources**: switches + add-by-URL field (on-screen keyboard); errors inline.

## Flow map (TV)
Launch → Discover (focus: first poster once loaded; the Movies switch while loading) → Select poster → Title (focus: first stream, or the first episode for a series) → Select stream → (Torrent start) → Player. Back at each step returns with the previous focus restored. Left at the content's left edge → rail. Back contract: close panel/search → pop route → at a tab root, focus the rail → on the rail, exit.

## Focus contract (every screen)
- **Initial focus** is named per screen (above). Never nothing.
- **Restore** the last-focused item after a route pop, per tab and per row.
- **Skeleton → content:** if focus was on a skeleton slot, it moves to the item that replaces it; if the user had moved on, it stays put.
- **Filtering** (chip, Movies/Series): focus stays on the control; Down enters results at the first item.
- **Removal** of the focused item (catalog switched off, download deleted): focus goes to the nearest neighbour, else the heading control.
- **Vertical moves** keep the nearest horizontal position. Rows remember their last focused item.
- **Up Next never takes focus.** No timed UI may move focus.
- Every actionable shows FocusFrame. No hover- or touch-only action. Nothing that holds focus may sit under persistent chrome (WCAG 2.4.11 focus not obscured).

## Player key map (TV)
| State | Select | Left / Right | Up / Down | Back | Play/Pause key |
|---|---|---|---|---|---|
| Bar hidden | toggle play, show bar | seek −/+10 s, time shown at once; held = accelerate | show bar (never volume) | exit player | toggle play |
| Bar visible | activate focused control | move focus | move focus; Down from the bar hides it | hide bar | toggle play |
| Tracks panel open | choose row | — | move in panel | close panel, focus back on Subtitles | toggle play |
Up Next countdown pauses while the tracks panel is open.

## State matrix (TV additions; phone unchanged)
| Screen | Loading | Empty | Error | Offline | Success |
|---|---|---|---|---|---|
| Discover | skeleton grid; focus on Movies | "No catalogs" + focusable **Add sources** | per-catalog inline error + Retry (focusable) | inline "You're offline" + Retry | grid, focus first poster |
| Title | skeleton panes; focus first skeleton row → real row | "No streams from your sources" + Add sources | per-source Retry rows | inline | streams |
| Anime (TV) | skeleton grid | "Kitsu catalogs off" + Add sources | inline Retry | inline | grid |
| Downloads | skeleton rows | "Nothing downloaded" | row error + Retry | still lists local files | rows |
| Sources | rows | n/a (Cinemeta locked) | inline under field | inline | rows |
| Player | buffering panel (existing) | n/a | recovery overlay (existing), its buttons focusable, first one focused | "Waiting for connection" (existing) | playback |
| External link, no browser | — | — | inline: the URL shown in full, "Open this on your phone" | — | — |

## Interaction and motion notes
- D-pad moves are high-frequency keyboard actions: the **focus ring appears instantly (0 ms)**. Only the poster lift animates: scale ≤ 1.03, 100 ms easeOutCubic, interruptible (implicit animation retargets). Rows scroll with `ensureVisible` 150 ms; key-repeat (held arrow) jumps without animation. Reduced motion: no scale, no scroll animation; the ring stays.
- Rail expansion: 160 ms ease-out on enter, 120 ms on exit (exit faster). Overlay with an opaque surface1 panel, no scrim.
- No stock dialogs; confirmations go through `showFlickSheet` (focus trapped inside, initial focus on the safe action).
- Text entry only where unavoidable (search, add-source URL); the field gets a full ring and Select opens the system IME.

## Allowed to scroll (TV)
Discover/Anime grid, stream list, episode list, Downloads, Sources. Headers scroll away with the grid and come back on return. Everything else fits 960×540 inside the safe insets.

## Applied
- **ui-ux-pro-max:** Focus States (visible ring on every control, incl. sheets), Keyboard Navigation (order = visual order, no traps), Focus Not Obscured (min) WCAG 2.2 AA, Focus Appearance (≥ 2 px perimeter, 3:1, so 3 dp `textPrimary` on #080808), Predictable back. No Flutter/TV entry in its stack DB: Flutter details come from the SDK (default Select/arrow shortcuts in `widgets/app.dart`).
- **apple-design:** Response (feedback with no latency, so the ring is instant), interruptibility (lift via implicit animations that retarget), spatial consistency (the rail expands from and collapses to its own edge), reduced motion (drop scale/scroll, keep the ring), Wayfinding (the selected marker stays visible apart from focus), Familiarity (Google TV rail + Back conventions).
- **emil-design-eng:** "Never animate keyboard-initiated actions" (ring 0 ms, held-key scroll unanimated), < 300 ms UI motion, exit faster than enter (rail 160/120), animate transform/opacity only (scale, not size), subtle scale (≤ 1.03, not 1.1).

---

# Spec (phase 3, approved direction 2026-10-31)
Mockups (untracked, ~1.5 MB each): design/tv/{discover,title,player,banner}.png. The critic's round-2 build notes override the renders' pixel geometry; the numbers below win.

## Device signal
`tv` (bool) from native `UiModeManager.currentModeType == UI_MODE_TYPE_TELEVISION`, method `tv` on the existing `flick/torrent` channel, read once in `main()` into `state.dart` (`device.tv`, overridable in tests). Width never turns a phone into TV.

## Tokens (`lib/theme.dart`, new `FlickTv`; colours unchanged)
| Token | Value |
|---|---|
| canvas | 960×540 dp; safe insets 48 h / 27 v (all chrome and focusable items inside) |
| type | hero 32/800, title 28/800, page 26/800, railHeading 22/700, card 18/700, body 16/500, meta 14/500 (nothing under 14) |
| rail | panel from the screen edge to x 120 (48 inset + 72 column; 24 dp icons in 48 dp targets centred at x 84), expanded to x 248 as an overlay |
| content | x 144 → 912 (768 dp): rail 120 + gap 24, right inset 48; posters 144×216, gap 12, 5 per row = 768 |
| title panes | art + facts 264 · gap 24 · streams/episodes 480 |
| player | sides 48, bar labels 16, time in `streamMonoStyle` tabular; tracks panel 320 |
| focus | ring 3 dp `textPrimary`, outside the element, 3 dp gap (background shows through); radius = element radius + 3 |
| lift | posters/cards only: scale 1.03, 100 ms easeOutCubic, retargets; none on chips, rows, buttons |
| selected | Flick slash: angled red (`activeMarker`) 3×16 dp bar left of the label/icon; same on rail, segmented switch, chips, source filter, tracks rows, Subtitles button when a track is on |
| motion | ring 0 ms; rail expand 160 ms easeOutCubic / collapse 120 ms easeInCubic; row/grid scroll on focus 150 ms easeOutCubic, 0 ms while a key repeats; reduced motion: no lift, no scroll/rail animation, ring unchanged |

`context.flick` stays the colour extension; add `context.tv` (bool) and `FlickTv` constants. Phone keeps `FlickTokens`/`FlickText` untouched.

## Kit (`lib/kit/focus.dart`)
- `FocusFrame({required Widget child, double radius, bool lift = false, VoidCallback? onActivate, FocusNode? node, bool autofocus})`: a `Focus`/`FocusableActionDetector` that paints the ring outside `child` when focused AND `FocusManager.instance.highlightMode == traditional`; `lift` scales child 1.03; Select/Enter → `onActivate` (via the default `ActivateIntent`). Used by posters, cards, chips, stream/episode rows, buttons that aren't already Material buttons (Material buttons get the same ring through the theme's focus overlay + `side` in `ButtonStyle` when `states.contains(focused)`).
- `FocusMemory`: remembers the last focused child per key (row/grid/tab) so returning restores it (`PageStorage`-style, keyed by a string).
- `FlickRail({destinations, selected, onSelect, bottom: Sources})`: a `FocusTraversalGroup`; collapsed 72; while any rail item has focus it expands to 200 over the content (Stack overlay, opaque surface1, no scrim); labels fade in. Selected = slash marker; focused = ring.
- `SlashMarker`: the 3×16 angled red bar.
- Sheets keep using `showFlickSheet` (focus trapped, initial focus on the safe action).

## Shell (TV)
`Row[FlickRail, Expanded(IndexedStack)]` in a Stack so the expanded rail overlays. Phone: unchanged `NavigationBar`. Back: (1) open panel/search/sheet closes, (2) route pops, (3) at a tab root with focus in content → focus the rail's selected item, (4) rail focused → `SystemNavigator.pop()`. Left from the leftmost content item reaches the rail (directional traversal); Right from the rail returns to the remembered item.

## Screen notes
- Discover (pilot): header (page 26) + Search action at right inside the inset; Movies/Series switch and chips use the slash; grid 5×(144×216) with title 18 and year 14 below; initial focus first poster after load, Movies switch while loading; filter changes keep focus on the control.
- Title: one display heading (title 28), "Streams" as a 22 label; chips sized to content; rows = play glyph + quality/source in `streamMonoStyle` 16 + facts 14, no chevron; cast line directly under the synopsis.
- Player: dark `surface2` Pause disc, white glyph, ring only when focused; played progress red; Up Next "Next" uses the phone card's stepped fill (accent, 1 s whole steps); never auto-focused.
- Anime on TV: Kitsu catalogs only (no Miruro search field).
- Rail icons: line glyphs, same stroke (Discover = explore_outlined, Anime = a line glyph not a filled face, Downloads = download_outlined, Sources = settings_outlined).

## Transitions
Unchanged from design/spec.md for routes. TV adds: rail expand/collapse (above), focus ring instant, poster lift. No new route animation.

## Ponytail cuts (not built)
Home hero / dwell backdrop on Discover, Quick Connect + LAN discovery (no Jellyfin), Miruro on TV, fixed-column row anchoring, low-RAM cache tuning (Phase C experiment only), goldens (the repo has none; widget tests at 960×540 instead), a separate TV APK.

## Tests
- 960×540 widget tests with `device.tv = true` and `tester.sendKeyEvent`: Discover initial focus; Right moves along the grid; Left from column 1 reaches the rail and the rail expands; Back at root focuses the rail; Select opens Title; Back restores the poster's focus; chip change keeps focus on the chip.
- Phone guard: 360×640, `tv = false`: NavigationBar present, no rail, Discover poster width 98.7 (existing test).
- Pure player key-map helper tests (when the player step lands).
