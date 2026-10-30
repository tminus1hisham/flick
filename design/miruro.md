# Miruro in Flick

## Verified approach (2026-10-30)

The repositories' `/api/secure/pipe` flow is stale on `www.miruro.to`: on the physical phone,
direct requests were blocked and a same-origin browser request returned 404. The current
public frontend uses `/api/v1/anime` and opaque catalog IDs instead. Flick uses that live
interface, with AniList supplying search metadata.

Public source references inspected:
- https://github.com/Shineii86/MiruroAPI/blob/main/src/helpers/pipe.js
- https://github.com/walterwhite-69/Miruro-API/blob/main/api.py
- https://www.miruro.to/assets/Button-BTdICcI9.js (transport)
- https://www.miruro.to/assets/Image-CTsHPc0v.js (catalog paths)
- https://www.miruro.to/assets/Seasons-ESvObR-R.js (episode and playback calls)

Current request shapes are significant: search uses `q=<title>&limit=15`, episodes use
`/<opaque-id>/episodes?limit=10000`, and playback uses `/<opaque-id>/episodes/<number>/play`.
The server rejected other tested limits with HTTP 400. Binary catalog responses are XORed
with the UTF-8 bytes of `miruro/catalog`, then decompressed with gzip. This format differs
from both reference repositories' pipe formats.

AniList-to-catalog matching checks `external_ids.anilist` for an exact ID, never the first
title match. Missing or ambiguous identities fail as unavailable. Only the first 15 catalog
search results are considered. Actual episode entries, provider names, sub/soft-sub/dub
tracks, server headers, subtitle URLs and download targets come from current responses.

## Browser boundary

Direct HTTP gets one attempt until browser access succeeds. Flick retains one Android
WebView session and automatically sends later same-origin requests through it, without
opening a dialog or repeatedly trying the blocked HTTP transport. URLs are still fetched
fresh for each Play/Copy action. Binary response bytes and content type return through a
dedicated method channel; browser cookies never leave it.

Only a genuine blocked/challenge response opens verification. The user completes the
ordinary site check and taps Continue once; a repeated block ends the request rather than
looping. Verification is not automated. A cancelled/failed session is discarded; successful
sessions survive episode changes and player navigation, and are released with the Activity.

The native bridge permits only catalog search, episode lists and playback paths on exact
allowlisted HTTPS origins. Messages must match the request ID, origin and main frame.
Ordinary requests expire after 30 seconds, visible verification after three minutes;
fetches time out after 20 seconds. Cancellation,
Activity destruction and late messages cannot complete a request twice. File/content
access and mixed content are disabled; TLS errors are rejected.

The current production entry uses `https://www.miruro.to`. Other historic origins are
available only in the diagnostic probe, without automatic domain rotation. Browser
support does not guarantee that a site check can be completed on every device/network.

## App behavior

Discover → Anime → AniList search → episodes → sources. Sub is selected initially;
provider and language choices remain explicit. The current playback endpoint returns
all provider/track combinations for the selected episode, so those choices are displayed
after resolving it. Every Play or Copy action resolves again and requires the selected
provider, track, server, quality and link kind still to exist.

HLS playlists, direct files and provider download pages have separate labels. Download
pages are copied as pages; Flick does not follow shorteners, assemble offline HLS files,
or claim that a missing provider download is available. `Copy URL + headers` puts JSON
with `url` and `headers` on the clipboard.

Only media request headers (`Referer`, `Origin`, `User-Agent`, `Accept`, `Accept-Language`)
are accepted, normalized per server. Browser Cookie and Authorization values are not
forwarded. Download targets and subtitles do not inherit another server's headers.
The existing player receives stream headers and subtitles through the existing handoff.

## Device evidence and repeatable probe

Device: Redmi Note 11 Pro (2201116TG), Android 13, Wi-Fi.
- App browser bridge decoded 222 Naruto episode entries and eight provider/track combinations.
- Animepahe's returned media URL failed at the CDN with HTTP 403.
- Aniwaves' returned HLS master/variant playlists decoded and a segment returned bytes.
- The existing player rendered Naruto episode 1; its first-frame metric was 11.8 seconds.
- After reconnecting the phone, the finished normal APK was installed without clearing data.
  Anime search, episode loading, Sub/Dub provider switching and fresh URL+headers copying
  passed through the completed screens. Aniwaves playback rendered video again, with a
  16.7-second first-frame metric. The copy confirmation was checked on-device; exact
  clipboard JSON/header contents are covered by widget tests, not an external downloader.
- No claim is made that every provider, episode or download page works.
- After the session-reuse change, a cold launch loaded Naruto episodes and sources and
  rendered episode 1 without a verification popup or Continue tap. Returning from playback,
  episode 2 sources, fresh URL+headers copying and playback also succeeded without a popup.
  A real expired-session challenge was not forced on-device; challenge gating and session
  failure/reset behavior are covered by unit tests.

`flutter run -t lib/miruro_probe.dart` runs the separate diagnostic entry point. Select
an origin and AniList ID, fetch episodes, resolve episode 1, then use Test media access
or Play. Diagnostic logs contain fixed stage labels and counts, never response bodies,
cookies, request headers or signed media URLs. The normal app starts from `lib/main.dart`.

`test/fixtures/anime` contains small curated subsets captured from the physical phone's
current responses. All HTTP URLs were replaced with `media.example` placeholders before
the fixture data crossed the browser inspection boundary. Tests exercise the transport,
exact identity mapping, source parsing, header isolation, bounded fallback, cancellation,
fresh clipboard data and stale UI responses.
