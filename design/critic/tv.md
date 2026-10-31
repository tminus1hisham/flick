# QA critic: TV Discover

## Round 1 (2026-10-31)
VERDICT: FAIL (craft 6). 7 findings, all fixed in 33b4459: ring follows the frame's node, keyed search frames, 48 dp header row, 12 dp caption gap, surface1 poster fill, grid at y 179, segmented Movies/Series track, rail items clipped to the sliding panel.

## Round 2 (2026-10-31)
VERDICT: FAIL
scores: distinct 8, hierarchy 8, motion 8, craft 8, states 8, theme 9, a11y 7, space 8

round-1 fixes: all verified (ring follows node: 10-rail-right-restores.png, 07-search-closed.png; keyed search frames: 07; 48 dp header: 01-launch.png, 03-search-open.png; 12 dp caption gap: 08-poster-focus.png; surface1 poster fill: code only; grid at y 179: 01; segmented track: 01, s-right.png; rail clip: 09-rail-expand-f1.png).

findings (ranked):
1. [a11y] The search "Close" X can't be reached with the D-pad (06-search-close-focused.png shows the ring still on the field). `_searchFieldFocus.onKeyEvent` only handles Down, and the text field keeps Left/Right for its caret. Back still closes search. Fix: on arrowRight with a collapsed selection at the end of the text, `focusInDirection(right)` and handle it. Test: open search, press Right on an empty field, expect focus on Close.
2. [motion] In the first frame of the rail expanding (09-rail-expand-f1.png), the focused item already has its full width but is clipped at x 120 dp, so the ring shows as an open bracket. Fix: in `FlickRail.item`, lerp the width with the panel animation (`lerpDouble(target, railExpanded - left - contentGap, _curve.value)`).
3. [states] No device evidence of skeleton, empty, error or offline, and no 1.3× font screenshot (judged from code: `_TvPosterSkeleton`, `_TvNotice`). r2-search-*.png show the launcher, not Flick: noise. Capture r2-skeleton.png, r2-offline.png and r2-font13.png before the next round.
4. [hierarchy, nit] The catalog filters are bare text. The mockup design/tv/discover.png has outlined chips. Fix: a 1 dp `outline` border at `controlRadius` on unselected `_TvChoice`.
5. [out of scope] Discover → Title lands on the phone layout (14-title.png): back arrow and Sources outside the safe inset, Material FilterChips, no ring on entry. For the Title pilot.

## Round 3 (2026-10-31, the user chose a third round)
Fixes: c860f46 (search Close by D-pad, rail item grows with the panel, outlined catalog chips), f594277 (tests 13 outline, 14 offline notice). Evidence: `round2/r3-*.png`.

VERDICT: PASS
scores: distinct 8, hierarchy 8, motion 8, craft 8, states 8, theme 9, a11y 8, space 8

round-2 findings: 1 fixed (r3-search-ime-closed.png → r3-search-close-focused.png; test 10), 2 fixed (rail.dart width and clip on one curve; test j; r3-rail-open.png), 3 fixed (r3-skeleton.png, r3-posters-loading.png, r3-font13.png; offline/empty from tests 14 and 8), 4 fixed (r3-launch.png; test 13).

nits (filed, not fixed; low severity):
1. [hierarchy] Catalog chip labels are the same 16 dp as Movies/Series; the mockup's chip row is lighter. Try 14 dp for non-segment `_TvChoice` labels.
2. [states] No device screenshot of the error/empty/offline notice (the emulator still loads catalogs in airplane mode; stage it with a dead addon URL). The notice is the plainest surface on the screen; consider the slash before its action.
3. [craft] The notice's Retry uses `controlRadius`; chips and switch use `FlickTv.segmentRadius`.
4. [out of scope] Discover → Title lands on the phone layout (Title pilot).

Evidence notes (round 2): 02-search-action-focused.png is mislabelled (shows Movies focused). Up does reach Search (s-up-from-movies.png). gates.txt: zero hits in the TV files. Motion tokens match the spec.
