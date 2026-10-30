# Step 05: extract shared widgets into `lib/kit/` (no behaviour change)
files: lib/screens/title.dart lib/screens/discover.dart lib/kit/sheet.dart lib/widgets.dart lib/theme.dart test/title_test.dart test/discover_test.dart

Anime screens will reuse these instead of copying them. Move, make public, keep rendering identical:
- `_Press` -> `lib/kit/press.dart` `Press`
- `_Chips<T>` -> `lib/kit/chips.dart` `FlickChips<T>`
- `_Segment` (discover) -> `lib/kit/segment.dart` `FlickSegment<T>`; it must accept 3 options (Movies | Series | Anime will use it in step 06) and still fit 360 dp.
- `_Poster` (discover; Hero + press scale) -> `lib/kit/poster.dart` `PosterTile`, taking plain fields (id/hero tag, title, image url, one optional secondary line) instead of a MetaPreview, plus a MetaPreview convenience constructor.
- `_EpisodeRow`, `_RowSkeleton`, `_EpisodeSkeleton` -> `lib/kit/episode_row.dart` / `lib/kit/skeletons.dart`. `EpisodeRow` gains optional `double? progress`, `bool watched = false`, `String? tag`, `Widget? trailing`; when all are null/false it renders exactly as before.
Update title.dart and discover.dart to use them. All existing tests must pass unchanged. Add a test that EpisodeRow shows the progress line, the watched mark (with a semantics label, not colour alone) and the tag.
