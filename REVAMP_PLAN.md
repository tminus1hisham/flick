# UI Revamp Plan

## Context
Flick: Flutter (3.41, Material 3) Android app. A Jellyfin client plus magnet-link torrent streaming. 10 screens. Used on a phone in the evening, often on flaky networks. Gates: `flutter analyze`, `flutter test`. Roles: Claude = senior UX designer (IA, flows, review), Codex CLI = chief UI designer (visual language, theme code).

## Findings
- No identity: default deepPurple seed, text-only "Flick" (main.dart).
- Home: equal poster strips, no resume progress, no hierarchy (home.dart).
- Detail: small poster, buried Play, text-only episodes (detail.dart).
- Libraries tab is a dead hop (library.dart). Magnet streaming hidden behind an AppBar icon (torrent.dart).
- Raw exception text, spinners everywhere, enum download states (`r.status.name`, downloads.dart).

## Design direction: Afterglow (approved 2026-10-28)
- Concept: a cinematic, artwork-led streaming-service feel. Torrent and download states use Relay's labelled stages and plain telemetry.
- Colour: bg #080808, s1 #141414, s2 #242424, outline #454545, text #F4F7FA / #B5B5B5, accent cinema red #D91C2B (white on it, 5.06:1), Play button white/black, success #71D6A2, warning #F3C46B, error violet #D6B3FF (always icon + label).
- Type: Manrope (bundled 400–800), Roboto Mono 500 for live numbers.
- Shape: 8 artwork / 12 controls / 24 sheets, stadium chips. Motion 120 / 180 / 280ms, no carousel or parallax.
- Not doing: Netflix's trademark red or "N" mark, condensed wordmark, Top 10 ribbons, fake progress, retry wording without a handler.
- Approved navigation changes: Browse replaces Libraries (library tabs); Sign out goes in a profile sheet; "Stream a link" on Home and Login; Home hero + Up next.

## Foundations
- `lib/theme.dart` (Codex): tokens, ColorScheme, component themes, `FlickColors` extension (`context.flick`), `playButtonStyle`, `monoStyle`, `FlickMark`.
- `assets/fonts/` + pubspec `fonts:` (OFL licences included).
- `lib/widgets.dart`: NetImage (fade-in, fallback), Seam, Skeleton, ErrorState + friendlyError, Poster, SectionHeader, PosterRow, ProfileButton, Loader(placeholder).
- `lib/jellyfin.dart`: `backdropUrl` (URL helper only).

## Page rollout
| # | Route | File(s) | Key changes | Status |
|---|-------|---------|-------------|--------|
| 1 | Home (pilot) | screens/home.dart, main.dart | hero, Up next, rails, skeleton, transparent bar, profile | ☑ |
| 2 | App shell + Browse | main.dart, screens/library.dart | Browse tab with library tabs + grid | ☑ |
| 3 | Detail | screens/detail.dart | backdrop hero, Play/Download, season tabs, episode rows with states | ☑ |
| 4 | Stream a link + Torrent | screens/torrent.dart | dialog copy, stage spine, telemetry, one-tap file rows | ☑ |
| 5 | Downloads | screens/downloads.dart | human states, mono bytes, storage line, overflow delete | ☑ |
| 6 | Search | screens/search.dart | empty / no-results states, grid | ☑ |
| 7 | Player | screens/player.dart | themed media_kit controls, top bar | ☑ |
| 8 | Login + Offline shell | screens/login.dart, main.dart | mark, inline errors, Stream a link | ☑ |

## Pilot learnings
- Chip `labelStyle` must be a plain TextStyle. A WidgetStateTextStyle loses its font family when Chip merges it.
- Hero: `Stack(fit: passthrough)` + `Column(min, spaceBetween)` pins the copy to the bottom of the 440dp hero.
- Verified via a mocked-server widget render with the real fonts (network artwork shows as placeholders in tests).

## Login notes (2026-10-29)
- Sign in / Sign up on one screen (segment switch). Sign up is visual-only: extra Confirm field, "Create account" disabled, note that the server admin creates accounts. Jellyfin has no public sign-up; `/Startup/User` (owner setup) is the path if it gets wired.
- `PosterDrift` is the one approved exception to "no carousel or parallax": 8 original textless thriller images generated for Flick (assets/posters, 144 KB), 4 columns at -12 deg, 24-40 s per poster, static under reduce-motion.
- No backdrop blur on the panel: the scrim is 85-98% opaque there, so blur would cost every frame and show nothing.

## Identity: Light Cut (approved 2026-10-29)
- Mark: solid red screen, two clipped corners, a "/" slit as negative space. Replaced the corner-bracket mark, which read as the player's fullscreen button. Codex drew it; UX checked it against "off" slashes (those lean "\" and cross the shape).
- Geometry lives in two places that must stay in sync: `_FlickMarkPainter` in theme.dart (24-unit optical redraw for 16-48dp, 108-unit master) and the vector drawables (ic_launcher_foreground, ic_launcher_monochrome, splash_mark).
- Next to the "Flick" wordmark, pass `label: null` so screen readers hear the name once.
- Launcher: adaptive icon with a flat #080808 background and a monochrome layer for themed icons; PNG fallbacks only for API 24-25 (minSdk 24).
- Splash: #080808 everywhere (the white launch background is gone). Android 12+ uses the 288dp no-background icon box. `SplashHandoff` (widgets.dart) draws the same master at 288dp in the window centre, fades the app in over 120 ms, then the mark out by 280 ms. No minimum duration, skipped under reduce motion.
- Notification icon left to background_downloader: its download/done/error/paused glyphs carry state, which beats a logo there.

## Constraints
Same API calls, handlers, download and torrent logic. No new packages.

## Verification
`flutter analyze` + `flutter test` per page, plus a mocked-server render at 390dp for screenshots.

## Result (2026-10-28)
All 8 rows done, one commit each on `ui-revamp`. Gates on the merged branch: `flutter analyze` no issues, `flutter test` 15 passed.
Not verified on a device: real artwork and scrims, Player top bar (no render captured), image fade-in, text scale above 1.3.
Follow-ups: promote duplicated `_gridDelegate`/`_GridSkeleton` (search + library) and `_Notice`/`_Message` into widgets.dart; floating `labelText` on filled inputs sits on the top edge (theme); search grid leaves slack under one-line titles.
