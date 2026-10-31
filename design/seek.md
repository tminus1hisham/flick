# 10-second seek: buttons and double tap

## Brief
**Job.** While watching, jump back to catch a missed line or skip ahead a little without dragging the seek bar. Same gestures as Netflix and YouTube: buttons beside play/pause, double tap on either side of the video, and further taps add more.

**Applies to** every playback in `PlayerScreen`: Jellyfin (streamed and downloaded), addon direct URL, torrent, Miruro.

**Inputs.**
- Bar buttons: `primaryButtonBar` becomes back 10 s · play/pause · forward 10 s, replacing media_kit's playlist skip buttons (no-ops here), in a fixed-width group (`primaryBarWidth`, 240 dp) so it stays inside the no-seek middle. `Icons.replay_10` / `Icons.forward_10`, 48 dp targets, labels "Back 10 seconds" / "Forward 10 seconds". TalkBack users depend on these: under TalkBack a double tap means "activate".
- Double tap: the left side seeks back, the right side forward. The middle (`seekMiddle`: a third of the width, never narrower than the button group plus 16 dp each side, widened by half the difference between the left and right insets, since media_kit's fullscreen pads its controls by a display cutout) never seeks, so a double tap on a button can't seek twice. Neither do the control bands. Top band: the top bar, `buttonBarHeight` 64 (fixed in our theme, so it doesn't grow at 1.3× text) plus the top view padding. Bottom band: the bottom bar 64 plus a 36 dp margin (the height of media_kit's seek bar, `seekBarContainerHeight`, so taps aimed at the seek bar never jump 10 s) plus the bottom view padding. Each further tap on a side while its burst is open adds another 10 s.
- What counts as a tap: a single pointer, counted on pointer-up; down→up movement within `kTouchSlop`; held under `kLongPressTimeout`. A pointer cancel, a second simultaneous pointer (pinch) or a drag resets the detector. A double tap is two such taps on the same side, the second pressed within `kDoubleTapTimeout` of the first's release (as Android measures it), `kDoubleTapSlop` apart.
- Controls during a burst: media_kit toggles its controls on every pointer-down, so the two taps of the opening double tap toggle twice, leaving the controls as they were. From then until the burst closes, the tapped side's zone absorbs pointers (an opaque region over exactly that zone), so further taps add 10 s without flashing the controls. The middle, with the buttons, and the bands stay live. A ±10 button press opens a burst too: for 400 ms a tap on that side adds another 10 s rather than hiding the controls (accepted: it reads as continuing the jump).

**One seek per burst.** Taps accumulate a target (`pending ?? position`, ±10 s per tap, clamped to `[0, duration]`). The player seeks once, 400 ms after the last tap. Torrent streams clear their piece deadlines on every seek, so one seek per burst matters there. Switching sides mid-burst continues from the pending target, and the ripple total restarts at 10.

**Haptic.** `HapticFeedback.selectionClick()` on each counted tap (buttons and double taps).

## State matrix
| State | Behaviour |
|---|---|
| Before playback starts (`duration == 0`) | Buttons and double taps do nothing: no ripple, no haptic. |
| Playing / paused | Seek; pause state unchanged. |
| Near the start | Clamp to 0:00; the ripple still shows the taps counted. |
| Near the end | Clamp to duration. Reaching the end is a normal completion, handled by the existing Up Next / completion path. |
| Buffering (BufferingPanel shown) | Double tap seeks (it's how people skip a stalled spot); the panel is `IgnorePointer` except "Try another source". media_kit fades the button bar out while buffering but keeps it tappable, so the ±10 buttons ignore taps and leave TalkBack while buffering. |
| Tracks panel open | The tap layer is ignored (`_panel`). |
| Up Next card shown | The card is above the tap layer and owns the bottom-right; taps on it never seek. The forward ripple sits mostly under the card (accepted: the card is the action there; the seek bar shows the jump). |
| Offline | Same as buffering. |

## Spec
### `SeekRipple` (lib/screens/seek.dart, visual by Codex)
```dart
class SeekRipple extends StatefulWidget {
  const SeekRipple({required this.side, required this.seconds, super.key});
  /// -1 back (left edge), 1 forward (right edge), 0 hidden.
  final int side;
  /// Running total of this burst in seconds (10, 20, 30 …); ignored when side == 0.
  final int seconds;
}
```
- The player keeps exactly one `SeekRipple` mounted, between the control bands (so the bars and the time stay readable) inside `IgnorePointer`, and sets `side`/`seconds` on every counted tap. It sets `side: 0` 400 ms after the last tap, when the seek is issued.
- The ripple owns its in/out animation: it appears on a side, slides the new total in each time `seconds` changes, fades out when `side` becomes 0 (keeping the last side and total while fading), and on a side switch fades out before reappearing on the other edge.
- Visual (Codex round 3, after the critic): a radial glow out of the tapped edge, vertically centred, with a 2 dp accent rim of 6 segments, one lit per counted tap (newest full accent, older at 0.45; the newest fades in over `stateDuration`, a colour change kept under reduced motion). The scrim is a plateau (0.88 → 0.80 to 0.78 r, then off by 0.92 r) under the whole label, so the label holds ≥ 5.4:1 and the icon 6:1 over a white frame, measured at 1.3× text. The total leads: Manrope 700 at 20 sp with tabular figures (not `monoStyle`: its space reads "10  s"); a small `Icons.replay` / `Icons.forward` under it. Afterglow tokens only.
- Motion: `FlickTokens.stateDuration` / `artworkFadeDuration`, `curveIn` / `curveOut`. With `MediaQuery.disableAnimationsOf`: opacity only, no slide.
- It speaks nothing (the haptic and the seek itself are the feedback). Wrap it in `ExcludeSemantics`.

### Bar buttons
`_SeekButton`s calling the State's `_nudge(-10 / 10)`. They listen to `player.stream.buffering` themselves (media_kit 2.0.1 never rebuilds its bars). A button tap shows the same ripple on its side.

### Tap layer (player.dart)
A `Listener(behavior: HitTestBehavior.translucent)` over media_kit's controls, injected through `Video(controls:)` so it also exists in media_kit's fullscreen route (ripple state is a `ValueNotifier` for the same reason); in the page it sits below BufferingPanel / UpNextCard / the tracks panel. A raw Listener stays out of the gesture arena, so media_kit's own tap-to-toggle-controls, drag and vertical gestures keep working. media_kit toggles controls on each pointer-down, so a double tap leaves the controls as they were (shown then hidden, or the reverse). media_kit's `seekOnDoubleTap` stays false.

Pure helpers, top level in player.dart, tested in test/player_test.dart:
- `int seekZone(Offset p, Size s, {required double top, required double bottom})`: -1, 0 or 1 (`top`/`bottom` are the band heights above).
- `double seekMiddle(double width)`: half the no-seek middle.
- `Duration nudgeTarget({required Duration position, Duration? pending, required Duration duration, required int seconds})`.
- `SeekBurst`: the burst's target, side and total; `nudge` (false with no duration), `settle` (the target, once).

## Out of scope
TV / D-pad and keyboard arrows, a configurable seek length, swipe-to-seek (media_kit `seekGesture`, left off).

## Known gaps
- A position event already in flight when a burst seeks can reset `_pos` to the pre-seek time; a new burst opened in those ~100–200 ms counts from there (code review round 1, low).

## Ponytail cuts
- The total under each bar button (planned earlier): it would need a notifier in a frozen bar. A button tap shows the side ripple instead.
- A custom double-tap recognizer in the gesture arena: a raw Listener plus the timeout is enough and can't break media_kit's gestures.
