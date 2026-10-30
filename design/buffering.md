# Buffering overlay: brief + spec delta

User request (2026-10-30): "come up with a plan with codex about how to handle buffering and have stable and seamless playing/streaming", then "start the next phases". Plan: `~/.claude/plans/come-up-with-a-twinkling-peach.md`, Phase 3. Codex's first-pass design is folded in below (section 3, marked where Claude changed it).

## 1. Brief delta (UX, Claude)

### Users and jobs
One user, on a phone, often on flaky Wi-Fi, watching an addon stream (torrent or direct HTTP). Job while the picture is not moving: **know why, know whether it is getting better, and have a way out when it isn't.** Today they get media_kit's stock spinner and nothing else.

### Scope
Addon playback only (`PlayerScreen.addonPlayback`). Jellyfin playback keeps its spinner and its existing "Use 1.5 Mbps" stall prompt. The fatal "Couldn't play this video" screen stays as is; the overlay never shows on top of it.

### Screen inventory (delta)
1. **Buffering panel (new, `lib/screens/buffering.dart`)**: one centred panel over the video, three phases:
   - **Starting**: from `open()` until the first frame. Copy: "Starting playback".
   - **Stalled**: mid-play, buffering for 600 ms or more. Copy: "Buffering". The last frame stays visible behind the panel.
   - **Offline**: buffering (starting or stalled) while the phone has no validated network. Copy: "Waiting for connection" / "Playback will resume automatically."
   Each phase shows a 4 dp progress rail (real progress toward resuming, or a static unknown rail) and, for torrents, one stats line "6 peers · 1.8 MB/s".
2. **Try another source (inline action in the panel)**: appears after 15 s in Starting or Stalled, or after 3 genuine stalls within 2 minutes. Pops the player, exactly like the error screen's "Choose another source" (TorrentScreen auto-pops when it auto-opened, so the user lands on the stream list).

### Flow map
```
Streams ─► (Torrent screen) ─► Player
Player:  Starting ──first frame──► playing ──buffering ≥600 ms──► Stalled ──resumes──► playing
           │                                     │
           ├─ no network ─► Offline ─ network back ─► (Starting | Stalled) ─► …
           └─ 15 s, or 3 stalls in 2 min ─► "Try another source" shows ─tap─► back to the stream list
mpv stops early (idle) ─► existing error screen (Retry · Choose another source)
```
Back (system or controls) always works; the panel never blocks it.

### State matrix
| Piece | Loading | Empty | Error | Offline | Success |
|---|---|---|---|---|---|
| Buffering panel | Starting / Stalled phase with rail | n/a | n/a: errors go to the existing error screen | Offline phase | panel fades out (120 ms) when playback moves, at whatever progress it had |
| Rail | real `bufferingPercentage` (mpv `cache-buffering-state`) once > 0 | static unknown rail (6 segments) before the first value | n/a | keeps the episode's last value at 40 % opacity | fades out with the panel; never forced to full |
| Torrent stats | hidden until the first status | hidden for direct sources | rate hidden when the status is older than 2 s | hidden (no measured rate offline) | n/a |
| Try another source | hidden until 15 s / 3 stalls | n/a | n/a | shown on the same rule | n/a |

### Interaction notes
- Panel is **inline over the video**, not a sheet or dialog: it is status, not a decision.
- Tapping the video still toggles media_kit's controls (seek, back, subtitles). The panel takes no tap except its one button, so it never steals a seek.
- Haptics: none. A stall is not a user action (Apple: feedback only where it earns its place).
- Screen reader: only the phase title is a live region; phase changes are announced once ("Buffering", "Waiting for connection"), never stats or progress.
- Allowed to scroll: no. The panel fits a 640×360 dp landscape viewport (the player is landscape-only) at 1.3× text.

### Applied
- **ui-ux-pro-max**: loading feedback for waits over 300 ms; never rely on colour alone (phase is in words, rail is secondary); 48 dp target for the only action; reduced-motion respected; no emoji icons.
- **apple-design**: feedback is status (four kinds: status/completion/warning/error, this is status); wayfinding: "how do I get out" answered by the button and Back; restraint: no haptics; reduced motion = no animation (`Duration.zero`).
- **emil-design-eng**: don't animate frequent events loudly: a stall can happen many times, so opacity only (enter 180 ms, exit 120 ms), no scale or slide; delay before showing (600 ms) so short hiccups never flash a panel; honest progress (real mpv value or a static unknown rail, never an invented percent); exit faster than enter.

## 2. Ponytail

Ultra on the UX:
- cut: Codex's three-stage spine in the player ("Finding peers / Preparing video / Filling buffer") → one Starting phase. Peer discovery and file pick already happen on the Torrent screen's spine, and the player can't tell "preparing" from "filling" honestly.
- cut: artwork under a scrim on Starting → plain player black. PlayerScreen has no artwork for addon items (the Item is built from an id and a name).
- cut: a percentage number → the rail alone, plus words. A number invites watching it.
- kept: the Offline phase, because "Buffering" forever on a dead network is the exact confusion the user complained about; it needs one tiny native method.
- kept: the 600 ms delay, because short hiccups on Wi-Fi are frequent and a flashing panel is worse than none.

Full on the code plan:
- reuse `StallDetector` (lib/stall.dart) for "3 stalls in 2 min"; reuse `PauseWait`'s genuine-stall rule (seeks don't count).
- reuse `TorrentEngine.status` (1 Hz poll only while the panel shows) and TorrentScreen's rate format (`_rate` moves to `lib/torrent.dart` as `formatRate`).
- media_kit's own indicator is replaced via `MaterialVideoControlsThemeData.bufferingIndicatorBuilder` (exists in media_kit_video 2.0.1), not hidden with a Stack trick.
- `online`: one method on the existing `flick/torrent` channel (ConnectivityManager, `NET_CAPABILITY_VALIDATED`; needs `ACCESS_NETWORK_STATE`), no package.
- no new animation controller: `AnimatedOpacity` + `AnimatedSwitcher` with `FlickTokens.stateDuration`-family tokens.

## 3. Spec delta

### Contract (logic ↔ visual)
In `lib/stall.dart` (pure, unit-tested):
```dart
enum BufferPhase { hidden, starting, stalled, offline }

typedef BufferView = ({
  BufferPhase phase,
  double? progress,      // 0..1 toward resuming in THIS episode; null = unknown
  ({int peers, int? rate})? stats, // torrent only; null = hide the line; rate null = not fresh
  bool offerSwitch,      // show "Try another source"
});

BufferView bufferView({
  required bool started,        // first frame seen
  required bool buffering,      // player.state.buffering
  required Duration waited,     // length of the current buffering episode (resets when one starts)
  required double percent,      // player.state.bufferingPercentage (0..100) in this episode
  required double? lastProgress,// the previous view's progress in this episode (offline keeps it)
  required bool online,         // last native check; true when unknown
  required bool repeatedStalls, // StallDetector(threshold 3, 2 min) tripped on genuine stalls
  ({int peers, int rate, Duration age})? torrent, // last status and how old it is
});
```
Rules:
- **hidden** when started and (not buffering, or waited < 600 ms).
- **starting** when !started; **stalled** when started, buffering and waited ≥ 600 ms.
- **offline** replaces starting/stalled only when that phase is already visible (the 600 ms suppression still applies) and !online.
- progress: percent/100 when percent > 0; offline keeps `lastProgress`; otherwise null. Never forced to full: on resume the panel fades out at whatever value it had.
- stats: null for direct sources or when offline; `rate` null when the status is older than 2 s (peers still shown).
- offerSwitch: phase != hidden and (waited ≥ 15 s or repeatedStalls).
Episodes: the **Starting** episode begins at `open()` (and at each Retry's `open()`) and lasts until the first frame or the error screen, whatever `buffering` says; its `waited`, ticker and polling run from `open()`. A **stall** episode begins when `buffering` turns true after the first frame. The player resets `waited` and `lastProgress` at the start of each episode.

In `lib/screens/buffering.dart` (visual, Codex):
```dart
class BufferingPanel extends StatelessWidget {
  const BufferingPanel({required this.view, required this.onSwitch, super.key});
  final BufferView view;
  final VoidCallback onSwitch;
}
```

### Visual layer (Codex proposal, revised after Codex review round 1)
- **Panel:** centred; 320 dp total width including 24 dp padding (rail and text use the 272 dp inner width); opaque `FlickTokens.surface1`; radius `FlickTokens.modalRadius`. Video stays visible around it. No decorative marker.
- **Type, centred:** phase title `FlickText.railHeading` (`textPrimary`): "Starting playback" / "Buffering" / "Waiting for connection". Offline adds `FlickText.body` in `textSecondary`: "Playback will resume automatically." Stats `FlickText.metadata` in `textSecondary`, numbers in `monoStyle`: "6 peers · 1.8 MB/s" (rate not fresh: "6 peers").
- **Spacing (4 dp grid):** title → (secondary 8) → rail 16 → stats 12 → action slot 16. The action slot is always reserved at 48 dp so the button appearing never recentres the panel.
- **Rail:** 4 dp high, inner width, fully rounded. Known: track `surface2`, fill `FlickTokens.progress` at `progress` width. Unknown: 6 equal segments with 4 dp gaps, all `surface2`, no fill and no motion. Offline: the rail at 40 % opacity.
- **Action:** "Try another source", the app's `OutlinedButton` theme (outline `FlickTokens.outline` 1 dp, foreground `textPrimary`, radius `FlickTokens.controlRadius`, theme pressed/focus overlays), full inner width, 48 dp high, fades in with the panel motion.
- **Motion:** enter `FlickTokens.artworkFadeDuration` (180 ms) with `curveIn`; exit `FlickTokens.stateDuration` (120 ms) with `curveOut`; phase text cross-fades with `AnimatedSwitcher` on the same tokens. `MediaQuery.disableAnimationsOf` → `Duration.zero`. Opacity only: no scale, slide or shimmer.
- **Input:** the panel ignores pointers except the button; taps pass through to the video controls. The moment the phase becomes hidden (or `offerSwitch` turns false) the button leaves hit testing and semantics, while its visual finishes the 120 ms exit. An unoffered button's reserved slot holds no interactive or semantic control (an empty 48 dp box).
- Tokens only; no `CircularProgressIndicator`, `LinearProgressIndicator`, SnackBar or dialog.

### Wiring (Claude's builder)
- player.dart: `bufferingIndicatorBuilder` returns `SizedBox.shrink()` for addon playback; a `BufferingPanel` over the video, under the error screen and the tracks panel; a 1 s ticker (plus a 600 ms one-shot), running for the Starting episode and while a stall episode lasts, advances `waited`, polls `engine.status` (torrent) and `online()`; `onSwitch` = `Navigator.pop(context)`.
- Native: `online` on the `flick/torrent` channel; `<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>`.

### Accessibility
Only the phase title is a live region (announced on phase change, not on stats or progress updates); button labelled; 48 dp; contrast of muted stats ≥ 4.5:1 on the panel surface; no clipping at 1.3× text in a 640×360 landscape viewport.
