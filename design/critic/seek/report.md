# QA critic: 10-second seek, round 1 (2026-10-31)

VERDICT: FAIL
scores: distinct 6, hierarchy 7, motion 7, craft 7, states 7, theme 8, a11y 8, space 7

**Evidence:** code and tests only. The player renders blank on the emulator, and the phone wasn't driven. Geometry assumes landscape at about 800×360 dp.

## Findings

1. **[distinct]** The ripple reads as YouTube's double-tap indicator: a flat half-disc in background at 0.8, a stock fast_rewind/fast_forward glyph, a small label, and no Afterglow accent or stepped motif.
   - **Fix:** a radial glow out of the tapped edge using scrim stops.
   - Add a 2 dp accent arc made of segments with grid gaps (like `_BufferRail`), one segment lit per counted tap: the newest in full accent, older ones at 0.45.
2. **[space/hierarchy]** The ripple fills the full height, so it covers the top bar, the seek bar and the time readout while the controls show.
   - **Fix:** position it between the control bands.
3. **[states]** With the Up Next card showing, the forward ripple sits under the card (360 dp wide, bottom-right).
4. **[craft]** Both bar buttons sit inside the double-tap zones. This causes a double count, and the absorber covers the button for 400 ms.
   - **Fix:** move the zone edges outside the buttons and pin them in tests.
5. **[states]** While buffering, media_kit fades the primary bar to 0 but keeps it hit-testable, so invisible ±10 buttons respond to taps and TalkBack can focus them.
   - **Fix:** ignore pointers and exclude semantics while buffering, with the button listening for itself (the frozen-bar pattern).
6. **[hierarchy]** The icon (32 dp) dominates the total (14 sp), and fast_rewind means continuous scan.
   - **Fix:** lead with the number (Manrope 700, 20 sp, tabular); make the icon smaller and use `replay`/`forward`.
7. **[motion]** The 4% pulse over 120 ms is barely visible, and a side switch teleports the disc.
   - **Fix:** an AnimatedSwitcher on the label (fade plus a 4 dp slide; opacity only with reduced motion), and on a side switch reverse, then forward.
8. **[theme]** Raw 48/36/64 in the bar buttons and the bands.
   - **Fix:** use `minTouchTarget`, `grid * 9`, and named band constants.

## Meets the bar
- Token motion, interruptible, with reduced motion as opacity only (tested).
- ExcludeSemantics, tooltips and 52 dp targets.
- FittedBox at 1.3× text; contrast above 11:1.
- Tap qualification and one seek per burst (tested); the duration-0 guard.

## Round 2 needs
- Landscape screenshots with the controls shown and hidden.
- One with the Up Next card showing.
- One at 1.3× text.
- A recording of a 3-tap burst.

# Round 2 (2026-10-31)

VERDICT: FAIL
scores: distinct 8, hierarchy 8, motion 7, craft 8, states 8, theme 5, a11y 8, space 8

**Evidence:** the renders 01–06 in this folder, the diff and the gates. The states score, the button/tap-layer parts of craft and a11y, and motion apart from render 06 rest on code alone.

## Findings
1. **[theme: contrast fail, capped at 5]** The label falls off the scrim: its alpha drops from 0.82 to 0.28 between 0.45 r and 0.68 r, while the label runs to 0.75 r. Over a bright frame the text is about 1.8:1 and the icon about 2.3:1.
   - **Fix:** a plateau `[0.88, 0.80, 0.30, 0]` at stops `[0, 0.78, 0.92, 1]`.
   - Add a bright-frame render.
2. **[motion]** The rim's newest segment hard-cuts. **Fix:** animate it over `stateDuration`.
3. **[theme]** A raw `iconSize: 48` on the play button.
4. **[craft]** The diff split `_BufferAhead`'s doc comment.
5. **[craft, optional]** A raw 64 in the Up Next padding.

## Round-1 findings
- Distinct, space, hierarchy, the buttons in the seek zones, and buffering: fixed.
- Motion: partly fixed.
- Up Next covering the ripple: accepted.

## Applied after round 2
- All five findings are fixed (decisions.md, Review round 2).
- New renders: 06-mid-step-20s, 07-bright-frame-left-30s, 08-bright-frame-right-60s-text1.3.
- Measured over the near-white frame: text ≥ 5.4:1, icon 6:1.
