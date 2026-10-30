# Step 06: A1, the Anime segment in Discover
files: lib/screens/discover.dart lib/anime.dart lib/state.dart lib/session.dart lib/widgets.dart lib/theme.dart lib/kit/press.dart lib/kit/chips.dart lib/kit/segment.dart lib/kit/poster.dart lib/kit/skeletons.dart lib/kit/sheet.dart lib/screens/account.dart test/discover_test.dart test/anime_test.dart

Plan section "A1". You own the visual layer; it must read as the same Afterglow family as Discover, not a second design language.
- Discover's switch becomes Movies | Series | Anime (FlickSegment). Remember the last segment (shared_preferences `discover.segment`). Anime keeps its own scroll position and state when switching away and back.
- New `lib/screens/anime.dart` `AnimeFeed`: anime-scoped search field (submit), chips `This season` (default) · `Airing today` · `Trending` · `Popular` · `Upcoming` · `Saved`, then the 3-column PosterTile grid with paging. Secondary line per poster: `Ep 5 of 12` from Progress when started, else `Ep 6 · Fri 18:30` (local time, absolute) when airing, else nothing. A `Continue watching` horizontal row above the grid only when `progress.recent(prefix: 'anilist:')` is non-empty.
- Tapping a poster pushes the A2 route `AnimeTitleScreen(id:, card:)`; create a minimal placeholder `lib/screens/anime_title.dart` (header + "Episodes" skeleton) that step 07 replaces.
- `Saved` chip: `saved.favourites` where type == 'anime'; guests see the existing sign-in prompt pattern.
- States (copy is fixed; use ErrorState / the existing notice pattern; Retry on each error):
  - loading: GridSkeleton
  - blocked: `Anime source is blocking this connection` / `Miruro refused the request. Try again later or on another network.`
  - changed: `Anime source changed` / `Miruro changed how it answers. Flick needs an update to read it.`
  - unreachable: `Can't reach the anime source` / `Check your connection, then try again.`
  - empty search: `No anime matches “<q>”`; empty Saved: `Nothing saved yet. Tap the heart on a show to keep it here.`
  - An anime error never affects the Movies/Series segments.
- Tests (fake `anime` swapped in state.dart): segment switch + persistence, skeleton then grid, each error copy, Continue row hidden when empty and shown when Progress has an anime entry, fits 360x640 without overflow.
