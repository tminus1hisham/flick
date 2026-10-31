# Main integration emulator checks — 2026-11-01

Tested main integration `5ccaea0`, then rebuilt with the native metadata restoration fix. Test video was recorded from the emulator; control audio was generated locally. Existing emulator app data was retained. No physical device was used.

## Found and fixed

Paused torrent downloads restored as `Failed: metadata not ready` after process restart. The files remained present. Native registration now pins the requested file before metadata arrives, configures its pieces once metadata is available, and validates deferred file indices before native file access. Invalid selections report a terminal error instead of keeping a foreground service running. Added the Kotlin regression `restoredSelectionWaitsForMetadataAndIsValidatedWhenItArrives`.

Reproduced on TV before the change (`tv-download-restored.xml`); after installing the fix, the same download restored as Paused, resumed, completed, and matched the fixture byte-for-byte (8,388,608 bytes; SHA-256 `4fbe4f38387be71be6d3429eda3f59b0262eacb8211dd495b79b9641f3c37194`). The foreground service stopped on completion. D-pad confirmation removed the test file and download row.

The combined Downloads screen also omitted native downloads from its storage total when direct downloads were present. A focused assertion reproduced `Expected 50, Actual 0`. The shared counter now includes native in-progress bytes and completed totals, including completed records reloaded after restart. Assertions cover all three cases.

## TV — Television_1080p_64, 1920×1080, density 2

| Check | Result |
| --- | --- |
| Cold launch, three main destinations plus Sources rail | Passed; initial focus Movies |
| Anime Kitsu catalogs; no Miruro search on TV | Passed |
| Anime Title → episode streams → Back | Passed; selected episode and grid focus restored |
| Sources reachable with D-pad; adding a manifest | Passed |
| Movie and series two-pane details; distinct play/download actions | Passed |
| Native audio playback, external subtitles, media Pause/Play | Passed; clock and control state verified |
| Subtitle language → Back → tracks → Back → bar | Passed; one layer per Back |
| Tracks at 1.3× text | Passed; font scale restored to 1.0 |
| Hidden-bar D-pad seek | Passed; clock moved from 0:17 to 0:26 |
| Manual Next episode | Passed; S1 E1 → E2 without stream list |
| Autoplay countdown | Passed; 10-second paused card, 7-second running card, then S1 E2 playback |
| Native torrent metadata, progress, pause, restart, resume, completion and deletion | Passed after fix |
| Native foreground download service | Passed; foreground while active, stopped when complete |
| Video decoding | Not verified: original emulator configuration reports EGL_BAD_ATTRIBUTE; SwiftShader retry did not produce advancing video |

The control and autoplay tests used a generated audio fixture so the emulator graphics failure could not masquerade as a successful video test. Actual H.264 video was attempted separately and failed to render. TV Downloads, Sources and Torrent start still use their existing generic layouts; this pass does not claim those screens have dedicated TV redesigns.

## Phone — Pixel_9a

Pixel_9a, 1080×2424 portrait / 2424×1080 landscape, density 420. Android System UI initially timed out under host memory pressure; it recovered after idle build processes were stopped. This was an emulator/system timeout, not a Flutter exception. Network settings began and ended with Wi-Fi on, mobile data on, airplane mode off; font scale restored to 1.0.

| Check | Result |
| --- | --- |
| Discover / Anime / Downloads shell, no sign-in | Passed |
| Discover and Anime catalog Retry | Passed; initial connection failures recovered |
| Miruro search | Passed; Naruto query returned results; provider playback not exercised |
| Sources via title, add manifest, remove manifest | Passed |
| Movie detail, favourite and like with no account | Passed; persisted across restart, then reverted |
| Native audio playback and external subtitles | Passed |
| ±10-second buttons | Passed; paused clock 1:18 → 1:28 → 1:18 |
| Side double-tap seek in fullscreen | Passed; 1:18 → 1:28; taps sent on one adb connection to meet the gesture window |
| Fullscreen / Back / portrait restoration | Passed; one Back left fullscreen, next returned to portrait Title |
| Failed stream and Retry after source recovery | Passed; controlled HTTP 503 became playable HTTP 206, with native start metric and subtitles |
| Direct download queue and completion | Passed; listed Ready offline |
| Downloaded file with both Wi-Fi and mobile data disabled | Passed; native audio playback clock advanced, then network restored |
| Native torrent and direct download in one list | Passed; both present at 1.0× and 1.3× text |
| Both completed downloads after app restart | Passed |
| Delete torrent while preserving direct download | Passed |
| Direct-download deletion | Passed; list returned empty |
| Combined storage total | Regression found in shared counter; fixed and covered by final passing Flutter assertions |

Phone control checks used audio-only media. This pass does not establish decoded video playback on the phone emulator or a physical device. It also does not establish live Miruro provider/CDN coverage, real-world torrent swarms, streaming a torrent while saving it, or Wi-Fi/LTE handoff.

## Evidence and tooling

Screenshots, accessibility trees, source/seed logs and emulator logs are in `.scratch/emulator-integration/`. The temporary local addon served emulator-created media at `http://10.0.2.2:8765`; its local torrent peer supplied real BitTorrent metadata and pieces. Sources were added through the app UI, and data checks used the emulator debug package only.

## Automated validation

- Kotlin: 25 tests passed (18 HttpTest, 4 MiruroPolicyTest, 3 DownloadsTest), zero failures/errors.
- Updated debug APK: Gradle assembleDebug passed.
- Flutter: all 263 tests passed after both fixes, including storage assertions for active, completed and restored native downloads.
- Static analysis: `flutter analyze lib test` passed with no issues.
- Final whitespace check passed.

## Cleanup

Temporary downloads, favourite and like were removed from the phone; its test addon was removed. TV test download was deleted and its data absence verified. The test addon was removed from TV as well; both test emulators and the local fixture server were stopped. Phone network and text-scale settings were restored. Large screenshots and test tooling remain local under `.scratch/emulator-integration/`, outside version control. No physical device was touched and nothing was pushed.
