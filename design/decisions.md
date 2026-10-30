# Decisions (ponytail gate + UX review of Codex's visual layer)

## Ponytail ultra, UX
- cut: Discover masthead "Discover" title → the search field is the header, profile avatar on its right. The tab label already says Discover; saves 56dp so ~2 poster rows show at 360×640 instead of ~1.5.
- cut: a separate Streams route for movies → streams inline on the movie's Title page.
- cut: per-stream detail screen → a tap plays.
- cut: addon catalogue browser (`addon_catalog`) → paste a manifest URL, as Stremio's "Add addon" field.
- cut: "Sources" entry in the profile sheet → the "Sources" button on Title/Streams and the "Add a source" empty state already reach it at the moment it is needed.
- cut: "Choose a video" stage when the stream names its file (fileIdx) → auto-play that file.
- kept: Discover as a 5th tab, because Browse is the Jellyfin library; mixing addon titles into it breaks "where am I". 5 is the bottom-nav limit.
- kept: inline Undo after removing a source, because removal is otherwise silent and irreversible without re-finding the URL (Agency).
- kept: catalogs from installed addons as extra chips, because it is a filter over manifests already fetched (a few lines).

## Ponytail full, code plan
- kept: 4 new files (addons.dart, discover.dart, title.dart, sources.dart); D2 and D3 share one stream list widget in title.dart.
- reuse: NetImage, Skeleton, friendlyError/ErrorState, monoStyle, scrims, chip/input/button themes, existing page transition.
- no new packages: `http` + `shared_preferences` cover the protocol and persistence.
- new tokens: only `FlickTokens.streamQualityWidth` (60) and `streamMonoStyle` (from Codex).

## Rejected from Codex's proposal
- Restyling the shell NavigationBar (marker above icon, no pill) for Discover: changes every tab's look, out of this feature's scope. Discover uses the existing themed bar.
- Trailing chevrons on stream rows (in the D3 render, not in Codex's written spec): the written spec wins, no trailing affordance; the whole row is the target.
- "|" separators in telemetry (D3 render): use the "·" of the movie render, matching the app's metadata lines.

## Accepted deviations from build-mobile hard rules (pre-existing app)
- The app has no `lib/kit/`, no presets and no theme changer; it went through the earlier UI revamp, not this pipeline. The new screens use no stock dialog, snackbar, picker or spinner at all, so no kit is needed for them. Kit + presets are a separate job.
- `gates.py` already fails on the existing files (theme in lib/theme.dart, Colors.* in older screens). Gate for this feature: zero hits in the new files.

## Bundled addons (user request 2026-10-29: "addons come full package")

Source: github.com/stremio/stremio-official-addons `index.json`. stremio-core's `Profile::default()` installs exactly this list (`addons: OFFICIAL_ADDONS`). Every endpoint probed live on 2026-10-29.

| Addon | Gives | Flick |
|---|---|---|
| Cinemeta | catalogs, title + episode metadata | **bundled**, locked on (as Stremio: `protected`) |
| Public Domain Movies | a movie catalog + torrent streams (`infoHash`, `fileIdx`) | **bundled**; also our legal end-to-end torrent test (The Kid, 1921, 1080p) |
| WatchHub | "where to watch" streams (`externalUrl`: Netflix, Rakuten, …) | **bundled**; rows open the service's app or site (Android intent via the existing Kotlin channel, no new package) |
| OpenSubtitles v3 | subtitles per video id | **bundled**; subtitles in the player (auto-pick device language, switch/off in a player panel) |
| OpenSubtitles (legacy v1) | old subtitles protocol | skip: superseded by v3 |
| YouTube | `channel` catalogs, `ytId` streams | skip: needs a YouTube extractor; media_kit can't play a ytId |
| Local Files | needs Stremio's desktop server on 127.0.0.1:11470 | skip: Flick's Downloads tab already plays local files |

Bundled addons ship as manifest snapshots in code, so they work on first launch with no fetch. Cinemeta is locked; the other bundled ones get an on/off switch on Sources (no remove/re-paste needed). User-pasted addons keep remove + Undo.

Not bundled: third-party torrent indexers (Torrentio and similar). None is part of the Stremio org; Stremio leaves them to the user, and Flick does the same via "Add a source".

## Optional sign-in / guest mode (2026-10-29, design/guest.md)

User decisions: comments left out (no backend); favourites + likes on Jellyfin for Jellyfin titles and on the device for Discover titles; first launch keeps Login with "Continue as guest".

- cut: comments → no store exists (Jellyfin and addons have none).
- cut: Home/Browse/Search for guests → hidden; guest shell is Discover + Downloads, no dead tabs.
- cut: lock badges on gated toggles → normal off state, gate on tap.
- cut: Favourites screen/tab → Discover "Favourites" chip + Home "Favourites" row.
- cut: dislike → like on/off only.
- kept: resume intent (the tapped action completes after sign-in), because re-tapping after a detour is the main soft-gate friction.
- kept: guest Downloads tab, because old downloads must stay playable.
- added: `lib/kit/sheet.dart` (`showFlickSheet`), the first kit piece: the gate and the guest profile sheet open through it, so new files have zero gates.py hits. Older sheets still call showModalBottomSheet directly.
- override of Codex (guest-visual.md): Detail toggles sit **below** Play/Download, not above. Play stays the primary action by the title (Netflix's Play, then My List order).
- override of Codex: the Title row is a small `_Saving` widget, not an inline ListenableBuilder, to keep `_hero` readable.
- ponytail: device favourites not keyed per account; Home's Favourites row refreshes on pull, not on return from Detail.

## Buffering overlay (2026-10-30, design/buffering.md)

Codex spec review: REVISE, REVISE, APPROVED (round 3).
- cut: three-stage spine in the player (Finding peers / Preparing / Filling) → one Starting phase; the Torrent screen already shows peer discovery and the player can't tell the stages apart honestly.
- cut: artwork under a scrim → player black; addon Items carry no artwork.
- cut: percentage number → rail plus words.
- cut (Codex): decorative 3 dp marker on the panel → none; red is reserved for measured progress.
- kept: Offline phase, because endless "Buffering" on a dead network is the confusion being fixed; one native `online` method, no package.
- kept: 600 ms delay before a mid-play stall shows, so Wi-Fi hiccups never flash a panel.
- kept (Codex): reserved 48 dp action slot, so "Try another source" appearing never recentres the panel.
- changed (Codex): opaque `surface1` panel instead of translucent; offline hides stats instead of showing a fake 0.0 rate; progress never forced to full on resume.
- ponytail: Jellyfin playback keeps media_kit's spinner and its 1.5 Mbps prompt; the overlay is addon-only.
- critic round 1 FAIL (space 6): reserved action slot cut → card above centre (`Alignment(0, -0.3)`) growing with `AnimatedSize`; Codex's fixed-top pin overflowed at 1.3× text, so the plain Align stays (the card's top moves ~22 dp when the button appears, animated).
- critic round 2 FAIL (craft 7); user chose fix + a 3rd round. Codex (UI lead) chose `streamMonoStyle` for peers/speed numbers over Manrope tabular figures, for consistency with the Torrent screen's telemetry; RobotoMono's wide decimal ("1.8") is accepted as the mono voice, as on the Torrent screen.
- button height is a 48 dp minimum, not fixed: a fixed height clipped the label's descenders at 1.3× text.
- critic round 3 PASS (distinct 8, hierarchy 9, motion 8, craft 8, states 9, theme 9, a11y 8, space 8). Fixed after: rail dims to 40 % with a fade; the panel is out of focus/semantics while the tracks panel is open. Left open (follow-up): the rail switches from filled to the unknown rail without a fade if progress resets to null after offline; mono decimal spacing.

## Up Next (2026-10-30, design/upnext.md)

User: Jellyfin and addon/torrent series; Autoplay switch in the player (card + addon tracks panel), device setting, default on; Netflix timing (card at T-30 s or Jellyfin's Outro marker, 10 s countdown, skips the rest). Codex spec review: REVISE, REVISE, APPROVED (round 3).
- cut: post-play takeover, synopsis/runtime on the card, "Are you still watching?", Previous episode, Next for Jellyfin offline, a settings screen.
- kept: resolve prefetch when the card appears; fallback to the next episode's stream list when no stream shares the bingeGroup (a wrong release is worse than one tap).
- override of Codex: the card always sits above the bottom bar's band (64 + 12 dp) and never moves; media_kit 2.0.1 keeps the controls' visibility private.
- Codex review: stepped countdown (1 s ticks, no tween) instead of a pause-aware interpolation; no press scale or resolving cross-fade; one guarded commit (pause, resolve, pop only if still the current route); typed `AddonNext` results; Wrap footer for 1.3× text.
- known: subtitles centred at the bottom can sit under the card's left edge during the last 30 s (usually credits).
- Review round (2026-10-31, code review FAIL then PASS-WITH-NITS; QA critic FAIL round 1: motion 6, distinct 7, states 7):
  - Episode handoff (Claude, UX): episode screens open on `EpisodeRoute` (lib/kit/route.dart). Moving on pops the player and torrent start screen with no exit animation (`popForNext`), and the next episode fades in over the background (`artworkFadeDuration`, `curveIn`), so the old stream list never shows. Back from it is a plain fade.
  - Override of Codex: the countdown seconds use the button font with tabular figures, not `monoStyle` (RobotoMono's space read as "6  s").
  - A failed thumbnail now removes the image and its gap (spec), via `NetImage.onError`.
  - The torrent start screen titles itself with the episode ("Slow Horses · S1 E3 · …") instead of "Stream a link". Its stock AppBar and raw file path stay: a redesign of that screen is a follow-up for Codex, not part of Up Next.
  - Leaving media_kit fullscreen (on its own or when the card appears) re-applies immersive landscape; media_kit's default showed the bars and unlocked rotation.
  - media_kit 2.0.1 never rebuilds its button bars on a theme change (inverted `updateShouldNotify`): anything in a bar that changes after the first build must listen for itself (the Next button does).
