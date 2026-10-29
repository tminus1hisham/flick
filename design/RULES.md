# Design rules: read before touching UI

- Colours, type, spacing, radius, motion: Afterglow tokens only (`lib/theme.dart`: `FlickTokens`, `FlickText`, `context.flick`, `monoStyle`). No raw `Color(...)` or `Colors.*` in screens.
- No stock dialogs, snackbars, pickers or spinners in new screens (`showDialog`, `AlertDialog`, `SnackBar`, `showDatePicker`, `CircularProgressIndicator`). Loading is a skeleton (`Skeleton` in widgets.dart) that mirrors the real layout; feedback is inline.
- Every screen ships loading, empty, error, offline and success states from the state matrix in design/brief.md.
- Screens fit 360×640 dp unless listed as allowed-to-scroll in design/brief.md.
- Motion: `FlickTokens.stateDuration` / `artworkFadeDuration` / `sheetDuration`, `curveIn` / `curveOut`; honour `MediaQuery.disableAnimationsOf`. Transitions follow the map in design/spec.md.
- 48dp minimum touch targets, spoken labels on icon buttons, selected state on chips and segments, no clipping at 1.3× text.
- Check: `python ~/.claude/skills/build-mobile/scripts/gates.py .` (new files must have zero hits; older files predate this rule).
