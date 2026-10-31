# QA critic: TV Anime tab

## Round 1 (2026-10-31, diff 4a4d634..763d5fb): FAIL
Scores: distinct 8, hierarchy 8, motion 8, craft 8, states 8, theme 7, a11y 7, space 9.

1. [a11y] Back up from the grid to the chips leaves the "Anime" title half off the top (1.0× and 1.3×): `tvReveal` reveals only the chip, and nothing focusable sits above it (Discover has Search in its title row). Fix: wrap the header in `RevealArea`; test Down ×3, Up ×4, title in view. **Fixed in 4551cdf, test 17 (fails without it: title at −19 dp).**
2. [theme] `Icons.local_florist_outlined` draws solid petals and leaves, heavier than the rail's line glyphs. Fix: `Icons.filter_vintage_outlined`. **Fixed in 4551cdf (`animeIcon`).**
3. [craft] `HeroMode` ignores which tab is visible; a title in two mounted grids gives two Heroes with one tag. Fix: `HeroMode(enabled: i == _tab)` per stack child in main.dart. **Fixed in 4551cdf (TV shell; the phone shell has the same pattern, not changed).**
4. [nit, hierarchy] Three posters read "Boku no Hero ..." alike. Two-line titles or the season in the year line. **Filed:** Discover's grid geometry is shared and passed; a two-line caption changes it for both tabs.
5. [nit, states] Empty state uses the generic `video_library_outlined`. **Fixed in 4551cdf (uses `animeIcon`).**

Evidence: `design/critic/tv/anime/0*.png`; the critic's own captures were in the session scratchpad.


## Round 2 (2026-10-31, independent Codex critic): PASS
Scores: distinct 8, hierarchy 9, motion 8, craft 8, states 8, theme 9, a11y 8, space 9.

No blocking findings. Supersedes the preliminary evidence-only FAIL after supplying enlarged-text screenshots, shared component source and executed tests.
- `r2-05-large-current.png`: 1.3x Anime heading/chips fit; Airing selected and focused.
- `r2-06-large-poster.png`: 1.3x focused poster ring and captions remain in view.
- `r2-navigation.mp4`: 25-second emulator navigation capture (not independently played by critic).
- Tests 18�19: large-text Title/Back poster focus and full-header restoration; loading/offline retain chip focus; D-pad Retry recovers. Existing tests 15�17 cover chips, disabled catalogs/Add sources and header reveal.
- Shared CatalogFeed and focus kit inspected for all states, semantics and reduced motion. Fixed dark theme contrast: primary/background 18.63:1, secondary/background 9.77:1, primary/surface2 14.44:1, secondary/surface2 7.57:1, slash/background 3.96:1.
- Design checker: 27 preexisting hits in theme/player/downloads; none in Anime or shell changes.

Limits: state coverage combines source and tests, rather than all emulator state captures. Motion assessed from code/tests. No physical TV or performance measurement. Long captions retain shared Discover ellipsis behavior.

Final gates: flutter analyze clean; flutter test 196 passed; Kotlin XML 22 passed with zero errors/failures; flutter build apk --debug succeeded. git diff --check clean.


## Hands-on emulator follow-up (2026-10-31)
Found grid Down escaping to rail at unbuilt/end rows; shared vertical traversal fixed, regression test 20 reproduced failure before fix. Independent focused code review found no blocking issue. Corrected build's repeated-Down/Left/Right/Up sequence passed on emulator; full suite 197 green, analyze clean, APK built. Evidence: `tv/anime/smoke/README.md` and screenshots 15-19.
