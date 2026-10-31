# TV Player delta — 2026-10-31

Approved direction: `tv.md` and `tv/player.png`; existing Flick tokens, focus kit and playback state remain the source of truth.

The TV player uses a remote key layer, a sparse title/progress/control bar, and a fixed right tracks panel. Phone controls keep their existing branch. Hidden Left/Right seek 10 seconds, accelerating to 30 after a second held; unknown duration shows controls instead. Select toggles once and reveals Play/Pause. Visible arrows traverse controls; Down hides. Controls hide after four idle seconds only while playing and outside panels, recovery and focused Up Next.

Back returns from language selection to its opener, then closes tracks to Subtitles, hides the bar, and exits. Tracks open on the current selection and trap directional focus. Up Next never takes focus; Up from the right controls enters it, Down returns, and disappearance restores Play/Pause. Recovery and Retry remain focusable. Subtitle selection, fetching, HTTP header policy, audio and autoplay reuse the existing player logic.

Implementation: `lib/player_keys.dart` holds the pure key/seek helpers; `lib/screens/tv_player.dart` owns the testable control layer. `player.dart` wires native playback and tracks; `upnext.dart` and `buffering.dart` use the shared TV focus frame. No dependencies added.

Checks cover key repeats, seek bounds/unknown duration, progress geometry, focus/Back, timers, current recovery, late offline states, Up Next and 900×500 at 1.3× text. Native rendering limitations and final evidence are recorded in `critic/tv-player.md`.
