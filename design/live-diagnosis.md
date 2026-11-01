# FCTV playback diagnosis and repair plan

Investigation and implementation: 2026-11-01. The initial findings below are retained as the investigation record; the implementation results at the end supersede its hypotheses.

## What we know

The user reports that game streams play in FCTV while Flick reports “This channel rejected direct playback. Try another channel.” In `Fctv.kt`, that message comes from `FctvPlaybackException` in the native HLS preflight, before `playLive` opens the shared player. Non-2xx responses, an invalid initial playlist, or exceeding four playlist/resource fetches can produce it. The message alone does not distinguish these causes.

The existing `.scratch/fctv_probe.py` was rerun during this investigation. It returned 301 football events, including 39 live events. Five sampled channel entries returned HTTP 200 playlists and HTTP 401 on their first media request. These entries included repeated TyR and DZ ES labels and shared a media host, so they are not five independent providers. The probe tried decoded original-stream metadata and APK-style headers. This is current desktop evidence, not a capture of the user's failing phone request or a matched FCTV/Flick channel comparison.

## Concrete differences in the code

| Stage | Flick | Decompiled reference APK |
|---|---|---|
| Source selection | `/api/stream/detail` with `withOriginal=false`; decode relay URL and sign its session | `PPManager` tries original-stream information with a matching playlist rule, then falls back to the signed relay |
| Media requests | One URL and static header map, handed directly to media_kit after preflight | `PPManager.p2pProxy` routes through the local media proxy with a custom HTTP client |
| Segment handling | Ordinary HTTP fetch of the first non-comment playlist URI | `PPNetInterceptor.actionIntercept` tries `HlsInjectFetcher`, then `CdnSmartLinkManager`, then an ordinary request |
| Runtime rules | Reads media headers from `/api/common/params` | Also applies configured playlist/segment URL rules, extra headers, country filtering, and CDN candidate selection/retries |
| Preflight | Rejects all non-2xx responses; redirects unsupported | Proxy/network layer has additional request and fallback behavior |

Reference sources are under `.scratch/fctv-decompiled/sources/com/rblive/common/manager/` and `.../http/p2p/PPNetInterceptor.java`. `com/p2pengine/sdk/M3u8Proxy.java` implements the local HLS server. These are decompiled sources, not verified runtime traces.

**Leading explanation:** our direct-stream adapter omits FCTV's media-delivery transformations. Successful catalog and playlist requests do not establish that their child URLs can be fetched directly. Static inspection establishes this implementation gap; it does not establish which rule is responsible for the user's working stream, or that P2P is required.

## Ordered plan

1. **Establish a matched baseline.** Record one currently live game's event/channel identity, FCTV version, device and network. Verify FCTV plays it, then Flick fails on the same entry immediately afterward. The connected phone currently has no package matching `fctv`; use the user's actual working installation or an emulator reference. Follow the project handoff's permission rule before driving the user's phone.
2. **Identify the exact failed request.** Add temporary bounded diagnostics around Flick's resolver/preflight: stage, HTTP status, playlist depth, redirect presence and redacted host/path shape. Keep session values, query strings, cookies and full media URLs out of logs. Record response rejection details only after redaction. Distinguish a redirect, nesting limit, playlist failure and segment 401.
3. **Trace only that channel's reference path.** Determine whether it selects original metadata or the relay, which runtime playlist/segment rule matches, and whether HTTP/CDN fetching succeeds without peers. Compare final URL transformation, header precedence, CDN candidates, redirects and session lifetime. The existing probe only approximates part of this behavior; original metadata alone already failed in its samples.
4. **Prove the smallest missing behavior outside the UI.** Extend a bounded diagnostic probe with the observed rule. Require consecutive valid media resources across playlist refreshes, including initialization/key resources when present. A playlist 200 or arbitrary nonempty response is insufficient. If this still fails, investigate the remaining observed reference behavior before committing to an implementation.
5. **Implement only the proven path.** Prefer a resolver/header correction if it covers every request. If each segment needs transformation, use a live-specific loopback proxy feeding the existing player; mirror the established loopback binding/lifecycle pattern without coupling live requests to torrent `Entry` state. Apply the same fetching policy to preflight and playback. Include child playlists, keys, initialization resources, ranges and redirects as required by the observed HLS format. Validate upstream URLs/headers, bound requests/retries, scope sensitive headers, and cancel/close resources on exit. Do not import the whole proprietary engine based only on static evidence.
6. **Acceptance.** Unit-test the reproduced rule and its rejected inputs, plus any proxy refresh/redirect/lifecycle behavior introduced. Verify fresh resolution on Retry. Run the applicable Flutter/Kotlin checks and build the APK after code changes. Require real video/audio on the matched channel for at least ten minutes, several playlist refreshes, Retry and Back/reopen; then check another independent source and Android TV. Report the tested source scope explicitly.

## Expected change scope

The primary repair belongs in `android/app/src/main/kotlin/dev/local/flick/Fctv.kt` and its Kotlin tests. A live proxy, if proven necessary, also needs ownership/disposal in `MainActivity.kt`. Review `lib/live.dart`, `lib/screens/live.dart`, `lib/playback.dart` and `lib/screens/player.dart` as callers; their current URL/header contract may already suffice for a loopback URL. Add Dart/UI changes only if that contract or user-visible errors change. Update `design/live.md` and `CLAUDE.md` with actual acceptance evidence.

No new dependencies, player replacement, UI redesign, ads, account features or full P2P implementation are planned. Backend changes and regional behavior can limit coverage; a successful sample must not be presented as support for every FCTV source.

## Implemented findings

- The public bootstrap has migrated from the APK's compiled API host. Flick now reads and validates the current host and refreshes runtime headers/CDN configuration every 15 minutes.
- Empty country/continent fields returned placeholder HTTP playlists. Using the APK's public bundled AS/ID fallback returned real signed HTTPS relays. No geographic lookup was needed or implemented.
- The real playlists expose encoded CDN candidate/path metadata. Applying the reference `_s2` signature produced HTTP 200 MPEG-TS media for DZ ES and TyR channel families. Optional HLS injection is disabled in the current public bootstrap; full P2P was unnecessary for these samples.
- `FctvMedia.kt` implements only the demonstrated HTTP/CDN path, with a bounded loopback HLS proxy, scoped headers, validated upstream destinations, redirect/range support, key/init handling, retry deadlines and lifecycle cleanup. The shared player contract remains URL plus headers.
- Native proxy tests cover URL rewriting, signature/region selection, credential scoping, byte ranges, redirects, keys/init files, rejection responses and cleanup. An ignored real-source Kotlin test fetched 20 distinct segments across ten playlist refreshes through the actual proxy.
- Longer desktop probes encountered a transient CDN timeout and subsequent source removal. These failures prompted bounded retries; source removal is not evidence of uninterrupted ten-minute playback. Physical-device acceptance remains separate from HTTP/media delivery checks.
- The phone emulator subsequently ran Cercle Brugge vs Royal Antwerp / DZ BE for more than eleven minutes. Read-only Dart heap snapshots showed advancing media_kit position (past 693 seconds), `playing=true`, `buffering=false`, 1280x720 video and no error; AudioFlinger showed Flick's active 48 kHz audio track. A forwarded request to the native proxy returned a real playlist before Back and failed after Back, confirming shutdown. The emulator's picture remained black with `EGL_BAD_ATTRIBUTE`; visible-picture/audible-output and physical-phone/TV acceptance are still unverified.
- Final checks: 271 Flutter tests, 39 Kotlin tests, clean Dart analysis, debug APK build, and the same 27 pre-existing design-gate findings. No dependencies were added and no physical phone was controlled.
- Fresh-launch check with the final APK: the same channel again reported 1280x720, `playing=true`, `buffering=false`, no error and position advancing from 24.1 to 32.4 seconds. Back again closed the proxy. Temporary debugger forwards were removed and the emulator started for this investigation was shut down.
