# Step 03: `Progress` store and player hooks
files: lib/session.dart lib/state.dart lib/screens/player.dart lib/anime.dart test/player_test.dart test/guest_test.dart

1. `Progress` in lib/session.dart next to `Saved`, with a global in lib/state.dart:
   - entry `({Duration pos, Duration dur, DateTime at, String title, String? subtitle, String? poster, String? parent})` keyed by a videoId (anime: `anilist:<id>:<n>`; `parent` = `anilist:<id>`).
   - `load()`, `entry(id)`, `watched(id)` (pos >= 90 % of dur; the position is kept), `record(id, entry)`, `recent({String prefix})` newest first, one per `parent` (the Continue-watching row), `clear(id)`. shared_preferences key `progress`, JSON; cap 200 entries, drop oldest.
2. `PlayerScreen` (dart-formatted file; keep it formatted), addon playback only, Jellyfin behaviour unchanged:
   - `final Duration? start;` used instead of `item.resumePosition` when given.
   - `final List<Skip> skips;` (default const []), stored for step 08.
   - `final void Function(Duration pos, Duration dur)? onProgress;` called every 10 s while playing, on pause, on `AppLifecycleState.paused`, and in dispose (with the last known position), never with dur == 0.
   - pure top-level helper `Skip? activeSkip(List<Skip> skips, Duration pos)` (start <= pos < end - 1 s; the first match).
3. Tests: Progress persistence round trip, 90 % rule, recent() grouping and order, cap; activeSkip edges. PlayerScreen can't be pumped (no libmpv) — keep logic in the helpers.
