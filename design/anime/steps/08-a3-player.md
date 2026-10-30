# Step 08: A3, skip pill and Playback source sheet
files: lib/screens/player.dart lib/screens/buffering.dart lib/screens/anime_title.dart lib/anime.dart lib/kit/sheet.dart lib/kit/press.dart lib/theme.dart test/player_test.dart test/buffering_test.dart test/anime_test.dart

Plan section "A3" (Up Next is NOT in this step).
- Skip pill (player.dart, addon playback only): while `activeSkip(widget.skips, pos)` is non-null, a pill bottom-right above the controls: `Skip intro` / `Skip outro`; tap seeks to the skip's end (+ lightImpact). Appears/leaves with the standard motion token, honours reduced motion, 48 dp target, visible even when controls are hidden.
- Playback source: `PlayerScreen` gains `final Future<PlayerSwap?> Function(BuildContext context)? onSwitchSource;` where `typedef PlayerSwap = ({String url, Map<String, String> headers, List<Subtitle> subtitles, List<Skip> skips});`. When set: a `Playback source` button in the controls, and BufferingPanel's "Try another source" calls it instead of popping. On a non-null swap the player reopens the new media at the current position (same path as `_retry`), keeping the subtitle choice off and re-running auto-pick.
- anime_title.dart supplies `onSwitchSource`: a showFlickSheet titled `Playback source` listing each provider for that episode × Sub/Dub (current one marked), one row each, 48 dp; picking resolves with that provider/lang (`Finding a source…` on the row; error copy inline with Retry) and returns the swap.
- Pure helper tested: `List<({String provider, String lang, bool current})> sourceOptions(AnimeEpisode sub, AnimeEpisode? dub, String provider, String lang)`.
- Jellyfin and torrent playback unchanged (no button, no pill when skips empty). Keep player.dart dart-formatted.
