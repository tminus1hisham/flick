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
| content | x 144 → 912 (768 dp): rail 120 + gap 24, right inset 48; posters derived (rev. 1: 140×210 at 960), gap 12, 5 per row |
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

## Spec revision 1 (answers Codex spec review round 1; these win over the sections above)
1. **Grid clearance.** The grid gets 10 dp padding on each side and on top/bottom, inside the 768 content area, so ring (6) + lift (~2.2) never clips. Posters are derived, not fixed: `w = (contentWidth − 20 − 4×12) / 5`, `h = w × 1.5` → at 960 wide: **140×210**, gap 12. Scroll views keep their default clip; the padding gives the ring room.
2. **Shell.** The rail base is a 120 dp column (48 inset + 72). Content has 24 dp left padding (content x 144 → 912). Expansion = a 248 dp opaque `surface1` panel stacked over the content; its labels fade + slide in (opacity/translate only, no width animation). The base column never changes width.
3. **Vertical budget (Discover, 540 tall).** 27 top inset · header 32 · 12 · switch row 40 · 8 · chips row 40 · 16 → grid starts at y 175. Cell = poster 210 + 8 + title 22 (1 line, ellipsis) + year 18 = 258; the second row is half visible (grid scrolls; the header scrolls away with it). **Title:** left pane fixed, no scroll: art 264×148 (16:9 backdrop, poster fallback), 16, title max 2 lines, 8, meta 1 line, 12, synopsis max 4 lines (ellipsis), 8, cast 1 line; right pane scrolls. **Other viewports:** every TV size is derived from the actual width (rail fixed, content = width − 192, posters from content width), so 720p/4K devices that report a different logical size still lay out; no letterboxing.
4. **Activation.** `FocusFrame` = `FocusableActionDetector(actions: {ActivateIntent: CallbackAction(onActivate)})`. On TV the app root adds `Shortcuts` overriding Select / Enter / numpadEnter / gameButtonA with `SingleActivator(key, includeRepeats: false)`, so holding Select never re-activates; arrow repeat stays on.
5. **One ring.** One `FocusRing` painter used by `FocusFrame`; Material buttons used on TV are wrapped in `FocusFrame` (no `ButtonStyle.side` variant). On TV, `FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional` at startup; phone stays automatic. The ring rebuilds on highlight-mode changes and is 0 ms on/off, independent of the lift.
6. **Traversal rules.** Inside grids and lists, Up/Down/Left/Right use the default directional policy (nearest item). Memory applies only to re-entry: (a) Right from the rail → the tab's remembered item (by stable item id), else its initial target; (b) route pop → the item that opened the route. Entering the rail (Left from the content's left edge, or Back at root) always lands on the selected destination, not the geometrically nearest. If a remembered item has been scrolled out of a virtualized list, scroll its index into view, then focus it. The rail keeps the ring while collapsing.
7. **Loading never moves focus.** Discover's initial focus is the **Movies/Series switch**; Down enters the grid at the first poster. No automatic transfer. The only "in place" replacement: a focused skeleton row/cell is swapped for the real item at the same index. If a remembered or focused item disappears → same index clamped to the new list, else the screen's initial target.
8. **Initial / fallback focus per screen and state:**
   | Screen | Initial | Empty | Error / all failed | Offline |
   |---|---|---|---|---|
   | Discover | Movies switch | Add sources | first Retry | Retry |
   | Search (Discover) | search field | the field (Back closes search) | field | field |
   | Title (movie) | first stream row (skeleton → real in place) | Add sources | first per-source Retry | Retry |
   | Title (series) | current season chip | (no episodes) season chip | Retry | Retry |
   | Anime (TV) | first Kitsu catalog chip | Add sources | Retry | Retry |
   | Downloads | first row | nothing focusable in content: focus stays on the rail | row Retry | first row |
   | Sources | first source row | n/a (Cinemeta locked) | the URL field | the URL field |
   | Torrent start | auto-open, else the Suggested file row | (no playable files) Choose another source | Retry | Retry |
   | Player | key layer (bar hidden) | – | recovery overlay: first button | Waiting panel: Try another source |
9. **Player.** Bar hidden → a root `Focus` key layer owns keys (Select = play/pause + show bar; Left/Right consumed: seek ∓10 s, after 1 s of hold ∓30 s per repeat, clamped to [0, duration − 1 s]; no seek when duration is unknown/0 → just show the bar; Up/Down = show bar). Bar shown → focus **Play/Pause**; auto-hide 4 s after the last key while playing (never while paused, panel open, or Up Next card focused). Up Next is reachable with Up from the bar's right side; it never takes focus itself; if it disappears while focused, focus Play/Pause. The tracks panel traps focus (FocusScope), opens on the current track row, closes back to the control that opened it.
10. **Back precedence** (one `PopScope` chain; Android system Back goes through it): IME open → close IME; search/panel/sheet open → close it (focus to its opener); series streams pane → back to the episode list on that episode; otherwise pop the route (focus restored per 6b); at a tab root → focus the rail; rail focused → exit. Sheets and recovery overlays trap focus.
**Tests added to the list:** held Select doesn't re-activate; held Right seeks/accelerates (helper); item deleted while focused (Downloads) → neighbour; results arriving after the user moved on don't steal focus; ring not clipped at the grid's first/last column (paint bounds inside the viewport).

## Spec revision 2 (Codex spec review round 2; wins over revision 1 where they differ)
3. Discover's second row is ~1/5 visible (not half); fine, the grid scrolls. **Title left pane fits:** art 148 + 16 + title 2×34 + 8 + meta 22 + 12 + synopsis 4×24 + 8 + cast 20 = 398 ≤ 486 (540 − 2×27). **Minimum supported logical viewport 900×500** (1080p and 720p TVs both report 960×540); below 520 tall the synopsis clamps to 2 lines.
4. **Activation repeats:** on TV, `MaterialApp.shortcuts` = `WidgetsApp.defaultShortcuts` minus every activator whose trigger is select / enter / numpadEnter / gameButtonA / space, plus those keys as `SingleActivator(key, includeRepeats: false): ActivateIntent()`. With no repeating entry anywhere in the hierarchy, a held Select activates once. Test pumps the real `FlickApp` shortcut hierarchy.
5. **One focus owner:** `FocusFrame` owns the `FocusNode` and the `ActivateIntent` action; any `InkWell`/Material button inside it gets `canRequestFocus: false` (or `focusNode: null` + `ExcludeFocus` for icon buttons) so it only paints press feedback. On TV the theme sets `focusColor`/`ButtonStyle.overlayColor[focused]` to transparent, so the stock focus visual never shows; only `FocusRing` does.
6. **Lazy lists:** TV grids/lists are `GridView.builder`/`ListView.builder` with `cacheExtent` ≥ one viewport height, so the next row is always built and the default directional policy can reach it; focusing it calls `Scrollable.ensureVisible` (150 ms, 0 ms while a key repeats, alignment keeps the item inside the padded area). Chip rows (few items) are non-lazy. Restoring an unbuilt index: jump the controller to the index's offset (fixed cell extents), then focus in the next frame.
7. If the focused item disappears and the list is now empty (e.g. the last download deleted) → the **selected rail destination**.
8. Torrent start loading target = **Choose another source** button (auto-open is an action, not a target). The state table's targets apply only **on entry or when the focused item is lost**; an error/offline state arriving later never moves valid focus.
9. **Tracks panel edges:** arrows at the panel's edges are consumed (Left/Right at its sides, Up at the first row, Down at the last); only Back leaves. Seek clamp: `[0, max(0, duration − 1 s)]`. Whenever the bar hides, focus returns to the hidden key layer.
10. **Tests (added):** a wrapped Material control has exactly one focus node and shows only the FocusRing; Down from the last built row reaches the next row; arrows at the tracks-panel edges don't leave it; deleting the last download focuses the rail; the bar's auto-hide returns focus to the key layer.

## Spec revision 3 (closes the Codex loop; 3 rounds used)
- **Lazy-list boundary fallback:** TV grids and lists override `DirectionalFocusIntent` with an `Action` that first tries the default policy; if focus would not move (no built candidate) it computes the target index (grid: ±columns, list: ±1), jumps the controller to that index's offset (fixed extents), and focuses the new item in the next frame. Default traversal everywhere else.
- **Title fit:** recomputed: 148+16+68+8+22+12+96+8+20 = **398 dp** ≤ 486 (Codex's 498 is an addition slip). At 500 tall with a 2-line synopsis: 350 ≤ 446. Tests check the Title left pane has no overflow at 960×540 and 900×500 and that the first/last poster's ring paint bounds stay inside the viewport.
- 960×540 is a device assumption (Android TV launchers render 1080p at xhdpi and 720p at tvdpi); the derived layout plus the 900×500 test covers drift.
- Codex review: round 3 ended REVISE on these two points only; both answered here. Recorded in design/decisions.md.
