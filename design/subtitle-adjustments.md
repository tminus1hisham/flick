# Subtitle timing and readability

The existing phone and TV subtitle panels contain a collapsed **Timing & appearance** action. Expanding it reveals timing, text size, contrast and a live text preview. Controls wrap in the narrow phone panel, remain scrollable at larger text, and use the house TV focus/reveal components. All action targets are at least 48dp; values and errors use live-region semantics. No new screen or dependency is introduced.

- Earlier/Later changes timing by 0.25 seconds, bounded to ±30 seconds. Positive means later. Reset timing restores zero for the current subtitle.
- Size changes in 25% steps from 75% to 200%; Reset size restores 100%. Dark background and dark outline keep light text readable. Appearance is saved together in Settings as `subtitleAppearance`, with readable defaults for invalid stored data.
- Appearance updates the actual `SubtitleViewConfiguration` on both Video widgets and the active video view parameters. Persistence failure keeps the applied appearance and offers an inline Retry.
- Off disables timing while appearance remains editable. Timing writes are serialized; changing subtitles supersedes stale queued changes, and failed native writes do not save a new offset. The adjustment widget is keyed by subtitle identity so an old error's Retry cannot change a different subtitle.
- Timing lives only in the player session. External files use their URL; embedded tracks use their ID in the current video. Changing files restores that file's own offset, Off applies zero, and playback Retry reapplies a recognized track/file's offset. Opening a new video/source creates a fresh timing session; changing live games/servers explicitly clears it. No subtitle URLs or timing values are persisted.
- Phone's Subtitles action exits media_kit's separate fullscreen route before opening the route-owned track panel, allowing these controls to work there without mounting duplicate panels. Playback continues on the underlying immersive player.

The installed media_kit player uses its default `libass: false`: mpv supplies plain subtitle text and Flutter renders it. The appearance controls therefore configure Flutter rather than setting mpv style options. Original ASS styling/positioning is flattened and image subtitles are unsupported by this renderer; the controls explain this limitation. This change does not switch rendering engines or strip additional formatting.

Timing uses mpv's [`sub-delay`](https://mpv.io/manual/stable/#options-sub-delay), in seconds. Positive and negative offsets are supported by the engine. Source checks: installed `media_kit` native player configuration and `media_kit_video`'s subtitle view/video view-parameter update API.

`test/subtitle_adjustments_test.dart` checks persistence/corruption, actual view configuration, timing separation/Retry/reset/bounds/failure/races, phone/TV controls at 1.3× text, 48dp targets and save-retry feedback. These tests do not mount native mpv. Physical timing/rendering, real subtitle formats, fullscreen transitions, TalkBack and remote acceptance remain device checks in backlog item 3.
