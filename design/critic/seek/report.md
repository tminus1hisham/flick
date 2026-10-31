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
