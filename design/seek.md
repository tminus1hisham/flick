# 10-second seek: buttons and double tap

## Brief
**Job.** While watching, jump back to catch a missed line or skip ahead a little without dragging the seek bar. Same gestures as Netflix and YouTube: buttons beside play/pause, double tap on either side of the video, and further taps add more.

**Applies to** every playback in `PlayerScreen`: Jellyfin (streamed and downloaded), addon direct URL, torrent, Miruro.

**Inputs.**
- Bar buttons: `primaryButtonBar` becomes back 10 s · play/pause · forward 10 s, replacing media_kit's playlist skip buttons (no-ops here). `Icons.replay_10` / `Icons.forward_10`, 48 dp targets, labels "Back 10 seconds" / "Forward 10 seconds". TalkBack users depend on these: under TalkBack a double tap means "activate".
- Double tap: left third seeks back, right third seeks forward. The middle third (play/pause and the two buttons) never seeks, and neither do the control bands. Top band: the top bar, `buttonBarHeight` 64 (fixed in our theme, so it doesn't grow at 1.3× text) plus the top view padding. Bottom band: the bottom bar 64 plus media_kit's `seekBarContainerHeight` 36 plus the bottom view padding. Each further tap on a side while its burst is open adds another 10 s.
- What counts as a tap: a single pointer, counted on pointer-up; down→up movement within `kTouchSlop`; held under `kLongPressTimeout`. A pointer cancel, a second simultaneous pointer (pinch) or a drag resets the detector. A double tap is two such taps on the same side within `kDoubleTapTimeout`, `kDoubleTapSlop` apart.
- Controls during a burst: media_kit toggles its controls on every pointer-down, so the two taps of the opening double tap toggle twice, leaving the controls as they were. From then until the burst closes, the tapped side's zone absorbs pointers (an opaque region over that zone only), so further taps add 10 s without flashing the controls. The middle third and the bands stay live.

**One seek per burst.** Taps accumulate a target (`pending ?? position`, ±10 s per tap, clamped to `[0, duration]`). The player seeks once, 400 ms after the last tap. Torrent streams clear their piece deadlines on every seek, so one seek per burst matters there. Switching sides mid-burst continues from the pending target, and the ripple total restarts at 10.

**Haptic.** `HapticFeedback.selectionClick()` on each counted tap (buttons and double taps).

## State matrix
| State | Behaviour |
|---|---|
| Before playback starts (`duration == 0`) | Buttons and double taps do nothing: no ripple, no haptic. |
| Playing / paused | Seek; pause state unchanged. |
| Near the start | Clamp to 0:00; the ripple still shows the taps counted. |
| Near the end | Clamp to duration. Reaching the end is a normal completion, handled by the existing Up Next / completion path. |
| Buffering (BufferingPanel shown) | Seeking is allowed (it's how people skip a stalled spot). The panel sits above the tap layer in the Stack, but it is `IgnorePointer` except "Try another source". |
| Tracks panel open | The tap layer is ignored (`_panel`). |
| Up Next card shown | The card is above the tap layer; taps on it never seek. Taps elsewhere on the side zones do. |
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
- The player keeps exactly one `SeekRipple` mounted in its Stack, inside `Positioned.fill` + `IgnorePointer`, and sets `side`/`seconds` on every counted tap. It sets `side: 0` 400 ms after the last tap, when the seek is issued.
- The ripple owns its in/out animation: it appears on a side, pulses each time `seconds` changes, and fades out when `side` becomes 0, keeping the last side and total while fading.
- Visual: a half-disc anchored on the tapped edge, vertically centred; the direction icon (`Icons.replay_10`-family or chevrons, Codex's call); the total in `monoStyle` ("10 s"; the space follows the countdown precedent in upnext.dart). Afterglow tokens only.
- Motion: `FlickTokens.stateDuration` / `artworkFadeDuration`, `curveIn` / `curveOut`. With `MediaQuery.disableAnimationsOf`: opacity only, no scale or pulse.
- It speaks nothing (the haptic and the seek itself are the feedback). Wrap it in `ExcludeSemantics`.

### Bar buttons
Stateless `IconButton`s calling the State's `_nudge(-10 / 10)`. No changing label, which avoids the media_kit 2.0.1 frozen-bar bug. A button tap shows the same ripple on its side.

### Tap layer (player.dart)
A `Listener(behavior: HitTestBehavior.translucent)` in the Stack just above `Video`, below BufferingPanel / UpNextCard / the tracks panel. A raw Listener stays out of the gesture arena, so media_kit's own tap-to-toggle-controls, drag and vertical gestures keep working. media_kit toggles controls on each pointer-down, so a double tap leaves the controls as they were (shown then hidden, or the reverse). media_kit's `seekOnDoubleTap` stays false.

Pure helpers, top level in player.dart, tested in test/player_test.dart:
- `int seekZone(Offset p, Size s, {required double top, required double bottom})`: -1, 0 or 1 (`top`/`bottom` are the band heights above).
- `Duration nudgeTarget({required Duration position, Duration? pending, required Duration duration, required int seconds})`.

## Out of scope
TV / D-pad and keyboard arrows, a configurable seek length, swipe-to-seek (media_kit `seekGesture`, left off).

## Ponytail cuts
- The total under each bar button (planned earlier): it would need a notifier in a frozen bar. A button tap shows the side ripple instead.
- A custom double-tap recognizer in the gesture arena: a raw Listener plus the timeout is enough and can't break media_kit's gestures.
