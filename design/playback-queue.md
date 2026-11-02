# Movie queue and live sidebar

Approved behavior: movies play in order after genuine completion; live games switch only on explicit selection. Episodes retain their existing Up Next behavior. No new dependencies.

## Movie flow

Movie source rows offer Add to playback queue separately from Download. Discover and movie player controls open the queue. The list supports Play next, movement, removal and inline clear confirmation. Duplicate additions report their existing membership. Restoring the app loads the ordered list without starting playback.

IMDb identities deduplicate across providers; custom IDs remain scoped to their configured provider. The registry retains movie identity/artwork, configured provider reference, source fingerprint and an optional Start over choice. It excludes resolved media URLs, request headers and subtitle links. Each launch requests fresh streams from the configured provider. Torrents match by hash/file index; direct sources require a unique filename/name/group or name/title/group match. Missing, ambiguous and disabled-provider results wait for Retry or an explicit source choice.

Opening or resolving a stream does not consume its queue entry. The shared player's first positive playback position confirms startup and removes the pending item. Errors and ordinary Back preserve it. Genuine completion advances exactly once, after any open queue/track panel closes. The route result flows through addon/direct/torrent and both offline movie callers. Resume checkpoints and the existing episode transition cleanup remain in use.

## Live flow

The panel has Queue and Server tabs. Queue lists the session's ordered games above the existing sport/team/game/league search, with explicit Add, Next game, movement and removal actions. A queued game loads channels and waits for a choice. Server shows the current game's channels, marks the selected channel and disables unavailable choices. Failed switches leave queued games in place with inline recovery.

Native `prepare` preflights a candidate proxy without replacing the active proxy; `commit` activates only that candidate, and `cancelPrepared` invalidates outstanding work and closes staged resources. Closing the panel cancels pending preparation. Back/activity destruction also clean up native resources. Retry refreshes the current selected channel, including after a successful server/game switch.

The sidebar owns a modal focus scope above normal/fullscreen playback. Back, Close and the outside barrier dismiss it and restore trigger focus. TV player shortcuts, timers and delayed focus requests are suspended while it is open. The pinned Back/Close controls and house focus rings remain visible at larger text. Loading uses skeletons; empty, error and save-retry feedback stays inline. Motion uses existing tokens and respects reduced motion. Queue contents are allowed to scroll; there is no scheduled switching or mixed episode queue.

## Mobile sheet (2026-11-02)

Movie and live playback queues use the house bottom sheet on mobile, including Discover's movie queue entry. It opens at 65% height, supports compact/expanded stops and a full-height view, and reserves at least 240 dp for controls on short screens. Dragging the handle resizes it; dragging down to the minimum closes it. The primary list expands the sheet before scrolling. The handle exposes accessible increase/decrease actions. Reduced motion skips handle animations and list snapping. Keyboard insets resize the available sheet space, and mobile live tabs scroll with the list. Back/Close remain pinned; movie actions and live source-switch cancellation retain their existing behavior. TV keeps the translucent right sidebar and its pinned tabs; Discover on TV keeps its full queue page.

## Verification and remaining acceptance

Mobile-sheet validation (2026-11-02): all 398 shared-tree Flutter tests pass, the Android unit-test gate passes (45 tests), and the debug APK builds. Seven touched UI/test files analyze cleanly. Gesture regressions cover portrait/landscape resizing, list scrolling, handle dismissal, focus restoration and unchanged TV presentation; live-panel tests cover keyboard search at 1.3× text, including Flutter's drag handoff when little vertical space remains. Existing analysis/design baseline findings remain unchanged. Physical touch/TalkBack acceptance remains outstanding.

Regressions cover persistence/corruption/write retry, source matching, duplicate/order mutations, startup retention, direct/torrent/offline handoff, completion deferral/exactly-once behavior, fresh live bridge identity, stale searches, failed switches, cancellation and phone/TV layout/focus at 1.3× text. Native session tests cover staging, stale commit rejection, cancellation, replacement and direct-source cleanup.

Final verification: 385 shared-tree Flutter tests and 45 Android unit tests pass; the debug APK builds, and all 19 changed queue/playback/test files analyze cleanly. Full analysis retains the existing `player_keys.dart:17` lint; design checks retain their existing 34 findings and none in new queue files.

Widget-rendered previews are local artifacts under `.scratch/queue-preview/`; they use a fake playback background and do not establish native video rendering. Physical phone/TV acceptance remains required for real-source switching, decoder/startup failures, movie completion across fullscreen/torrent/offline routes, audio/subtitle continuity and TalkBack. Do not drive the user's physical phone or use paid mobile data without permission.
