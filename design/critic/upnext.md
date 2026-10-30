# Up Next: QA critic reports (2026-10-31)

## Round 1: FAIL
scores: distinct 7, hierarchy 8, motion 6, craft 8, states 7, theme 9, a11y 8, space 8
1. [motion] handoff built from stock routes: player pop, torrent pop, MaterialPageRoute push; the old stream list shows between (06).
2. [states/distinct] every autoplay lands on the torrent screen's stock AppBar "Stream a link" with the raw season-pack path (06).
3. [states] a failed thumbnail leaves NetImage's plain tile; spec says remove image + gap.
4. [states] no device evidence for "Finding next episode…".
5. [hierarchy] "6  s": RobotoMono's wide space (01, 02).
Passed with evidence: 40 % fill at 6 s, 1.3× text fits, Autoplay off, Watch credits, bar order, autoplay into E2, tracks panel row, one live-region identity node.

## Round 2: PASS (from code and tests; no new device captures)
scores: distinct 8, hierarchy 9, motion 8, craft 8, states 8, theme 9, a11y 8, space 8
1–5 fixed (2 partly: title only; the start screen redesign is a Codex follow-up). Remaining notes:
1. [motion] the old torrent screen showed during the release await → fixed after the round (blank background while handing off, caa0a86).
2. [motion] system bars flash / rotation unlocks between two torrent episodes → follow-up with the start screen redesign.
3. [states] evidence 01, 02, 06 predate the fixes; re-capture on the phone (see CLAUDE.md Next).
4. [motion] the torrent screen's push to the player is still the stock transition → follow-up with the redesign.
