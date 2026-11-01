# Live sports through FCTV

Flick's Live destination browses FCTV sports events on phones and Android TV. It uses the existing player for directly accessible HTTP(S) streams. Live player controls hide seeking and duration, retain embedded audio/subtitles, and resolve a fresh source on Retry. Addon subtitle searches and Up Next are absent for live playback.

## Source and protocol

Assessed local `com.fctv77.app-release-323-v3.0.323.apk`, package `com.fctv77.app`, version 3.0.323 (323), SHA-256 `30f18beae073838d17713db1cc4a1e78f22367b5a9c0df06aa85557feb072571`. JADX output and probing scripts are ignored artifacts under `.scratch/`. JADX finished with 49 errors; the relevant API definitions, protobuf schemas, URL decoder, and session signer were readable.

`Fctv.kt` exposes `flick/live` operations `events(sport)`, `channels(sport,eventId)`, and `resolve(sport,eventId,id,site)`. `lib/live.dart` converts these into typed Dart records. API networking runs on a native worker and closes on activity destruction. Sessions remain in memory; the adapter does not log media URLs or session values.

- The APK's public Firestore bootstrap document supplies the current data origin (`https://apis-data10.tcpwe138stya.ru` during the repair). Flick refreshes it and media configuration every 15 minutes, validates the API origin, and retains its last origin if bootstrap is unavailable.
- `/api/common/bs` returns the version for code 100 (event lists) or 102 (event details).
- `/sfver{query-md5-prefix}{version}/api/match/live` and `/api/match/detail` use sorted query parameters and protobuf response envelopes. Only event metadata and channel fields are decoded; scores, odds and advertisements are ignored.
- `/api/stream/detail` resolves a channel immediately before playback. Empty region fields returned placeholder streams in the investigation. Flick uses the APK's bundled AS/ID fallback without querying the user's location. URL transport uses ROT47 plus an eight-character prefix. HTTPS relay URLs use the server-issued `rb-session` and the APK's AES-CTR token format.
- `/api/common/params` supplies current request headers, including the runtime iframe origin/referer override and CDN configuration. API requests receive these headers too. The compatibility user agent uses the expected client-version format without sending the device timezone.
- A bounded protobuf reader handles varints and length-delimited fields and skips fixed-width fields. HTTP responses are capped at 4 MiB with 15-second timeouts.

Football is the initial sport. The selector includes all 19 sport codes defined in the APK. Events load on the first tab visit, sport selection or manual refresh, with live events first. Stale replies do not replace the current sport. Phone navigation has four destinations; the TV rail adds Sources as the fifth destination.

## Media delivery and limits

The repair identified two concrete failures: empty region fields returned placeholder HTTP streams, and real signed relays required CDN segment handling. The bundled fallback produced real HTTPS HLS playlists. Their `_ctump`, `_ctuph` and `_ctutt` metadata supplies candidate CDN hosts/path; Flick applies the APK's `_s2` signature with the current configured salt. CDN selection accepts the fallback region and worldwide entries. Actual country-based routing and the optional HLS injection engine are not implemented.

`FctvMedia.kt` serves registered HLS resources through a random session URL bound to loopback. It rewrites child playlists, media URIs and quoted URI attributes (including audio, keys and initialization files), applies bounded CDN retries, preserves byte ranges, and follows bounded redirects. Sensitive headers remain scoped to the original origin; upstream private addresses and HTTPS downgrades are rejected. Four workers, a 4096-resource cache, per-resource deadlines, read limits and a stalled-client watchdog bound resource use. Media bodies are buffered up to 32 MiB. The same transport checks playlists, key/init dependencies and a media resource before the player opens. Back, Retry and activity destruction close owned resources.

Errors distinguish playlist/media status failures from unsupported playlists. Native diagnostic logs include operation, exception class, stage and status, without upstream URLs, session tokens or headers. Accessibility of one resource remains a preflight check, not a guarantee that an entire broadcast will remain available.

The APK's separate live API, proprietary P2P engine, optional HLS injection strategies, WebViews, ads, accounts, payments, recording and downloads remain excluded. Source availability and the provider's public bootstrap/configuration remain external dependencies.

Repair evidence and remaining acceptance checks are recorded in `live-diagnosis.md` and the project handoff. The real Kotlin proxy fetched 20 distinct live segments across ten playlist refreshes; this establishes media delivery, not physical-device video/audio acceptance.

## Checks

- Dart: native bridge mapping, fresh resolution, lazy loading, late-response rejection, retry/empty/error states, large-text layout, TV activation and focus restoration.
- Player: live termination is recoverable with unknown duration; TV controls hide duration and ignore seeking even when duration is known.
- Kotlin: real protobuf envelope/version fixture, invalid wire data and UTF-8, URL decoding/validation, and nested HLS child URL validation.
- Regression gates: Flutter analysis and full tests, Kotlin unit tests, debug APK build, and existing design gates. Emulator evidence and final results are recorded in the project handoff.
