# Up Next: brief + spec delta

User request (2026-10-30): "add auto next feature that can be turned on or off and also a next episode button similar to netflix". Plan: `~/.claude/plans/plan-to-add-auto-glistening-magpie.md`. User decisions: both Jellyfin and addon/torrent series; the Autoplay switch lives in the player (on the card, and in the addon tracks panel), saved on the device, default on; Netflix-style timing (card 30 s before the end or at Jellyfin's Outro marker, 10 s countdown, skips the rest).

## 1. Brief delta (UX, Claude)

### Users and jobs
One user on a phone, watching a series episode, often several in a row. Job at the end of an episode: **get to the next one without leaving the player and without picking a stream again**, and be able to stop that when they want to watch the credits or stop for the night. Job mid-episode: **skip to the next episode** in one tap. Today the player stops on the last frame; the user backs out to the episode list, taps the next episode, and (addon) picks a stream again.

### Scope
- Series episodes only: Jellyfin `Episode` items (streamed or downloaded, online) and addon/torrent episodes opened from `StreamsScreen`. Movies, pasted magnets and anything without a next episode show nothing new.
- Jellyfin offline (downloaded file, no server): no next episode, nothing new.
- Out: intro skip, "Are you still watching?", a settings screen, post-play takeover screen.

### Screen inventory (delta)
1. **Next episode button (player bottom bar):** right side, before the fullscreen button. Visible once a next episode is known. Tap: pauses, then plays the next episode (via the card's "Finding next episode" state when the stream still has to be found).
2. **Up Next card (new, `lib/screens/upnext.dart`):** over the video, bottom-right, from `upNextAt` until the episode ends. Content: next episode thumbnail (when known), "S1 E3" + title, primary **Next episode** action (the countdown fills it while Autoplay is on), **Watch credits** (closes the card for this episode), **Autoplay** switch.
3. **Tracks panel row (addon playback):** "Autoplay next episode" switch, the same setting.

### Flow map
```
Episode playing ──position ≥ upNextAt──► Card (Autoplay on: 10 s countdown | off: waits)
   │                                        ├─ countdown ends / tap Next ─► resolving ─► next episode plays (player replaced)
   │                                        ├─ Watch credits ─► card gone for this episode; plays to the end; stops on last frame
   │                                        ├─ seek back before upNextAt ─► card gone, countdown reset, Watch credits forgotten
   │                                        └─ video ends while counting ─► next episode plays at once
   └─ tap Next episode (bottom bar) ─► card in resolving ─► next episode plays
resolving (addon): same addon's streams for the next video ─► first stream with the same bingeGroup ─► plays
                   no bingeGroup / no match / fetch failed ─► next episode's stream list (StreamsScreen)
Back from the next episode ─► the stream list (or Jellyfin detail) the user started from.
```
Back always works and cancels a countdown or a resolve in flight.

### State matrix
| Piece | Loading | Empty | Error | Offline | Success |
|---|---|---|---|---|---|
| Next button | hidden until the next episode is known (Jellyfin: one request at player start) | hidden: no next episode (last episode, movie) | hidden: lookup failed | hidden for Jellyfin offline; addon shown (resolve falls back to the stream list) | shown |
| Card | "Finding next episode…" while resolving (button disabled, countdown full) | n/a: no card without a next episode | n/a: a failed addon resolve goes to the stream list | as Error | Autoplay on: countdown; off: static Next button |
| Thumbnail | `NetImage` fade | no thumbnail: the text column takes the width | image error: same as empty | as Error | shown |
| Autoplay switch | n/a | n/a | write failure ignored (setting stays for the session) | works (device setting) | toggling on restarts the countdown from 0; off stops it |

### Interaction notes
- The card is **inline over the video**, not a sheet or dialog: the video keeps playing under it and stays visible.
- The countdown runs only while the video is actually playing and the tracks panel is closed (pause, buffering, panel open → it holds). Stremio/WCAG: content that advances by itself needs a stop control (Watch credits, Autoplay off) and stops while the user is busy with something else.
- Haptics: `lightImpact` on a manual Next tap (button or card), same as a stream row tap. None for autoplay (not a user action) or the switch (the Switch's own feedback).
- Screen reader: the card is a live region announced once on appear ("Up next, S1 E3, Title"); the countdown is not announced per second; the Next action's label includes the seconds left ("Next episode in 7 seconds").
- The card ignores taps outside its own controls, so taps on the video still toggle media_kit's controls.
- Allowed to scroll: no. The card fits a 640×360 dp landscape viewport (the player is landscape-only) at 1.3× text, beside the bottom bar.

### Applied
- **ui-ux-pro-max**: auto-advancing content needs a stop control and pauses on interaction (Animation: Auto-Rotating Content Controls); autoplay costs data on flaky Wi-Fi, so it can be switched off (Sustainability: Auto-Play Video); 48 dp targets; never rely on colour alone (the countdown is also in the label).
- **apple-design**: agency (Autoplay on/off, Watch credits, Back always out); feedback utility (haptic only on the user's own tap); spatial consistency (card enters and leaves from the same edge); reduced motion = cross-fade, no slide.
- **emil-design-eng**: the card appears once per episode (occasional → standard motion, under 300 ms, exit faster than enter); a countdown is constant motion → linear; buttons scale slightly on press; never animate from nothing (opacity + small offset).

## 2. Ponytail

Ultra on the UX:
- cut: Netflix's post-play takeover (video shrinks, full-screen next-episode page) → one card over the video.
- cut: synopsis and runtime on the card → "S1 E3", title, thumbnail.
- cut: "Are you still watching?" after N autoplays. Add it if the user falls asleep to it.
- cut: a Next button for Jellyfin offline (no server to ask).
- cut: a Previous episode button.
- kept: the resolve starts when the card appears, so the countdown never ends on a spinner on good networks.
- kept: fallback to the next episode's stream list, because a wrong guess (playing a different release) is worse than one extra tap.

Full on the code plan:
- one pure helper file `lib/upnext.dart` (nextVideo, bingeMatch, upNextAt, upNextView); no new state-management.
- the player knows nothing of Jellyfin or addons: it gets a `Future<NextUp?>` and pops with whatever `NextUp.resolve()` returns; the caller's `play()` loops on that result.
- the countdown rides the player's existing 1 s `_ticker` pattern; no AnimationController for the fill beyond an implicit animation.
- the setting is one `bool` on `Session` (already owns SharedPreferences).

## 3. Spec delta

### Contract (logic ↔ visual)
In `lib/upnext.dart` (pure, unit-tested):
```dart
typedef NextEpisode = ({String label, String title, String? thumbnail}); // label "S1 E3"
typedef NextUp = ({
  NextEpisode episode,
  Duration? outro,                        // Jellyfin Outro start; null = unknown
  Future<Object?> Function() resolve,     // what the player pops with; called once, cached
});

Video? nextVideo(List<Video> videos, String id);              // sorted by (season, episode); never steps from season ≥ 1 into season 0
AddonStream? bingeMatch(List<AddonStream> streams, String? group); // null group → null
Duration? upNextAt(Duration duration, {Duration? outro});      // valid outro (≥ 50 % and ≤ duration − 5 s) else duration − 30 s; null when duration < 3 min

const countdownLength = Duration(seconds: 10);

typedef UpNextView = ({
  bool visible,
  double? countdown,   // 0..1 elapsed; null = Autoplay off (static button)
  int secondsLeft,     // for the label and semantics
  bool resolving,      // "Finding next episode…"
});

UpNextView upNextView({
  required Duration position,
  required Duration duration,
  Duration? outro,
  required bool dismissed,   // Watch credits for this episode
  required bool forced,      // the bottom-bar button was tapped
  required bool autoplay,
  required Duration counted, // countdown time accumulated while playing and the panel was closed
  required bool resolving,
});
```
Rules: visible when `forced`, or when not dismissed and `position ≥ upNextAt`. `countdown` = `counted / countdownLength` clamped, null when !autoplay (and when forced: it plays at once). The player resets `counted` and `dismissed` when the position drops below `upNextAt` (seek back), and fires when `counted ≥ countdownLength`, when the video completes while visible with Autoplay on, or on a Next tap.

**Binding rules after Codex review round 1** (these win over anything above):
1. **Countdown is stepped.** `counted` grows by 1 s on each player tick in which the card is visible, Autoplay is on, no commit has begun, the video is playing, not buffering, and the tracks panel is closed; a countdown-end commit needs the same eligibility. The fill and seconds change only on those ticks (no tween), so a hold needs no extra signal. Reduced motion and normal motion look the same for the fill.
2. **Completion.** A completion that `stoppedEarly` calls a failure goes to the error screen and never advances. A genuine completion with the card visible, Autoplay on and not dismissed fires at once, unless the tracks panel is open; then it fires when the panel closes (re-checking dismissed and Autoplay). After completion nothing is playing, so a card that becomes visible later (late lookup, late duration) with Autoplay on fires at once.
3. **Re-evaluation.** The view is recomputed on every tick, position event (including position 0, handled **before** the existing `p <= 0` early return), duration change, completion and when the `Future<NextUp?>` resolves.
4. **Prefetch vs commit.** The player calls `resolve()` once, when the card first becomes visible (or at commit, whichever comes first), and caches the future. Nothing navigates and no resolving UI shows until commit. Addon `resolve()` never throws: any failure becomes the stream-list pick result.
5. **One guarded commit** for the bar button, the card button, countdown end and completion: ignore if already committed; pause; `resolving = true`; await the cached future; then pop only if `mounted`, `ModalRoute.of(context)?.isCurrent == true` and the commit token is still the live one (Back/dispose invalidates it). Late results are dropped. A seek back does not cancel a commit already made.
6. **Typed results.** `lib/playback.dart` declares `sealed class AddonNext` with `NextStream(AddonStream stream, Playback playback, Addon addon)` and `PickStream(Meta meta, Video video)`. Jellyfin's resolve returns the next `Item`. The player stays generic (`Object?`); each caller pattern-matches its own result.
7. **Torrent.** `TorrentScreen._play` captures the player's result, keeps the `stopStream` cleanup, and pops itself with any non-null result (whether auto-opened or not), only if it is still the current route; a null result keeps today's behaviour.
8. **Jellyfin loop** repeats the whole preparation per item: `downloads.localPath`, refresh via `item()` when online, build `Future<NextUp?>` (`nextEpisode` + the **current** item's `outro`, in parallel), push the player.
9. **Accessibility.** The episode identity ("Up next, S1 E3, Title") is a separate, stable live-region node announced once; the seconds live only on the Next action's label, outside any live region. When the card hides or the tracks panel opens, the card leaves focus and semantics; focus returns to a player control.
10. **Footer** is a `Wrap`: Watch credits and the Autoplay control share a row, and stack when 1.3× text does not fit. Contrast checked for `onAccent` on both `surface2` and `progress`, and `textSecondary` on `surface1`.
11. **Motion cut** (Codex 13): no press scale and no resolving cross-fade; themed ink feedback only. The card keeps its enter/exit (opacity + 8 dp, reduced motion: opacity only).

In `lib/screens/upnext.dart` (visual, Codex):
```dart
class UpNextCard extends StatelessWidget {
  const UpNextCard({required this.view, required this.episode, required this.autoplay,
      required this.onNext, required this.onDismiss, required this.onAutoplay, super.key});
  final UpNextView view;
  final NextEpisode episode;
  final bool autoplay;
  final VoidCallback onNext, onDismiss;
  final ValueChanged<bool> onAutoplay;
}
```
Plus the bottom-bar `Next episode` button (visual, Codex), used in both the Jellyfin and addon bars.

### Visual layer (Codex, round 1; Claude overrides marked)

**UpNextCard**

Use the buffering panel’s opaque `FlickTokens.surface1` surface: video brightness must not change text contrast. Radius `controlRadius` (12 dp); no elevation, border, glow, gradient or extra scrim. Red earns its place as countdown progress.

- Width: `grid * 90` (360 dp), clamped to the available safe width.
- Padding: `railGap` (12 dp) on every side.
- Placement: bottom-right inside the player’s `SafeArea`, with 12 dp right margin, bottom margin `64 + 12` dp above the bottom safe inset, **whether the controls are shown or hidden**. *Claude override:* media_kit 2.0.1 keeps the controls' `visible` flag private (no callback), so the card cannot follow the bar; it always clears the bar's band and never moves. The player host owns this placement; `UpNextCard` owns its contents.
- Only actual controls consume taps. The header, thumbnail and unused surface pass taps through to the player.

Content, top to bottom:

| Element | Specification |
|---|---|
| Episode header | Minimum 54 dp high. Thumbnail left; metadata and title vertically centred beside it. |
| Thumbnail | When supplied: 96 × 54 dp, 16:9, `BoxFit.cover`, `artworkRadius` (8 dp). Gap to text: 12 dp. Use `NetImage`; loading uses the matching `Skeleton`. Missing or failed artwork removes the image and gap, giving text the full width. Retain the header’s minimum height. |
| Episode label | Exact supplied label, e.g. **S1 E3**. `FlickText.metadata`, `textSecondary`. |
| Title | 4 dp below label. `FlickText.cardTitle`, `textPrimary`. **One line maximum**, ellipsis; full title remains in semantics. |
| Primary action | 12 dp below header. Full inner width; minimum height 48 dp, `controlRadius`. Horizontal padding 12 dp, vertical padding 8 dp. `skip_next` icon, 20 dp; 8 dp gap; **Next episode** in `FlickText.button`. |
| Footer | 4 dp below primary action; minimum height 48 dp. **Watch credits** left; **Autoplay** label and switch right. |

Do not add an “Up next” heading, synopsis or runtime. The episode identity and primary action provide the hierarchy.

**Primary action and countdown**

With Autoplay on, the button is a `surface2` track with a solid `context.flick.progress` fill growing left-to-right, clipped to the button radius. Fill width is elapsed countdown fraction: **6 seconds left means 40% filled**. It has a straight leading edge and no shimmer or pulse.

Keep the icon and label in `onAccent`, painted above both regions without changing colour as the edge passes. Display `secondsLeft` as **6 s** at the trailing edge in `monoStyle`, reserving space for **10 s** so the label never shifts. The entire button is one action; the seconds are not a separate badge. Its spoken label is “Next episode in 6 seconds”; avoid per-second live announcements.

With Autoplay off, use `context.flick.playBg` and `playFg`, matching Flick’s play action. Remove the seconds and fill; centre the icon-label group.

**Watch credits and Autoplay**

Watch credits uses `FlickText.button`, `textPrimary`, and a text-button target at least 48 dp high. Allocate 144 dp of footer width, including 8 dp horizontal padding. It dismisses the card for this episode without interrupting playback.

After a 12 dp gap, the remaining footer width contains the right-aligned Autoplay control: `FlickText.metadata` in `textSecondary`, 8 dp gap, and a padded Material `Switch`.

Explicitly theme the switch:

- On: `accent` track, `onAccent` thumb.
- Off: `surface2` track, `outline` track outline, `textSecondary` thumb.
- Preserve Material’s padded touch target. Label the combined control “Autoplay next episode”; tapping the label also toggles it. Expose one semantic switch.

Turning off removes the countdown immediately. Turning on restarts it from an empty fill and **10 s**.

**Finding next episode…**

When `view.resolving` becomes true, preserve the card geometry and episode header. Replace the primary action’s icon, label and seconds with centred **Finding next episode…**, using `FlickText.button`.

The countdown is full and stationary. Keep `onAccent` text on the full progress surface, overriding default disabled opacity so the status remains readable. Disable repeated Next actions, Watch credits and the switch while the committed resolve is in flight; keep their layout. Back remains available to cancel. Do not add a spinner or an invented progress estimate.

Background prefetch while counting does not show this state. A failed resolve follows the existing stream-list fallback.

**Bottom-bar Next episode button**

In both player bars, keep the position indicator left and the right-side order **Subtitles → Next episode → Fullscreen**.

Use a transparent `TextButton.icon`: `skip_next` at 20 dp, 8 dp gap, **Next episode** in `FlickText.button`, `textPrimary`, 12 dp horizontal padding and minimum height 48 dp. Width follows the scaled label; do not copy a fixed-width control. Keep the full label at 640 × 360.

Show only when the next episode is known. It follows the bar’s auto-hide and has no countdown or red fill. Its accessible label is “Play next episode”. On tap, pause playback and show the card’s resolving state; disable this button during that resolve.

**Motion**

- Enter: opacity 0 → 1 and an 8 dp upward settle, `artworkFadeDuration` (180 ms), `curveIn`.
- Exit: reverse toward the same bottom edge, `stateDuration` (120 ms), `curveOut`. Remove interaction, focus and semantics immediately.
- Artwork: use the existing `NetImage` fade, `artworkFadeDuration`.
- Resolving label: cross-fade over `stateDuration`, without resizing the card.
- Countdown: interpolate linearly between 1-second updates. On pause, buffering or tracks-panel open, cancel the active interpolation at its displayed fraction and hold **both fill and seconds** still. Resume from that fraction using eligible playback time; never catch up through paused time. The visual host must supply the running/held signal—unchanged integer ticks alone cannot freeze an in-flight tween.
- Press: existing themed ink feedback plus scale to 0.98 over `stateDuration`; restore on release. Keep hit bounds unchanged. Manual Next uses the specified `lightImpact`; autoplay adds none.
- Reduced motion: cross-fade only, no translation, position tween or press scaling. Step the fill on each eligible tick. Freeze it while held. Honour `MediaQuery.disableAnimationsOf`.
- `sheetDuration` is unused: this overlay is not a sheet.

**640 × 360 dp at 1.3× text**

With artwork, the inner width is 336 dp; the text column gets 228 dp. The scaled header needs 53.4 dp: 20.8 dp metadata + 4 dp gap + 28.6 dp title. It fits the 54 dp header.

Total card height is **190 dp**: 24 padding + 54 header + 12 gap + 48 action + 4 gap + 48 footer. With zero safe insets, its top is **94 dp**. Add device safe insets before applying these margins.

Use minimum control heights and explicit compact padding, not fixed-height buttons with the theme’s larger vertical padding. Honour text scaling; ellipsise only the episode title. Keep the full card out of focus and semantics while the tracks panel is open.

Mockups (illustrative; dimensions and tokens above win): `design/mockups/upnext-autoplay.png`, `design/mockups/upnext-controls.png`.

### Wiring (Claude's builder)
- `AddonStream.bingeGroup` from `behaviorHints.bingeGroup`. `Playback.meta`. `play(…, {Addon? addon})` loops on the popped result: an `AddonStream`-carrying result → `play` again; a pick result → `StreamsScreen(meta, video)`.
- TorrentScreen pops itself with the player's non-null result.
- Jellyfin: `nextEpisode(Item)` (`/Shows/{seriesId}/Episodes?startItemId=&limit=2`), `outro(id)` (`/MediaSegments/{id}?includeSegmentTypes=Outro`), both null on any failure; detail.dart `play()` loops on a popped `Item`.
- `Session.autoplayNext` (`autoplayNext` pref, default true).

### Accessibility
Card is a live region announced once; Next action label includes seconds left; 48 dp targets; Switch labelled "Autoplay next episode"; contrast ≥ 4.5:1 for secondary text on the card surface; no clipping at 1.3× text in 640×360; card out of focus/semantics while the tracks panel is open.
