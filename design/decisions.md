# Decisions (ponytail gate + UX review of Codex's visual layer)

## Ponytail ultra, UX
- cut: Discover masthead "Discover" title → the search field is the header, profile avatar on its right. The tab label already says Discover; saves 56dp so ~2 poster rows show at 360×640 instead of ~1.5.
- cut: a separate Streams route for movies → streams inline on the movie's Title page.
- cut: per-stream detail screen → a tap plays.
- cut: addon catalogue browser (`addon_catalog`) → paste a manifest URL, as Stremio's "Add addon" field.
- cut: "Sources" entry in the profile sheet → the "Sources" button on Title/Streams and the "Add a source" empty state already reach it at the moment it is needed.
- cut: "Choose a video" stage when the stream names its file (fileIdx) → auto-play that file.
- kept: Discover as a 5th tab, because Browse is the Jellyfin library; mixing addon titles into it breaks "where am I". 5 is the bottom-nav limit.
- kept: inline Undo after removing a source, because removal is otherwise silent and irreversible without re-finding the URL (Agency).
- kept: catalogs from installed addons as extra chips, because it is a filter over manifests already fetched (a few lines).

## Ponytail full, code plan
- kept: 4 new files (addons.dart, discover.dart, title.dart, sources.dart); D2 and D3 share one stream list widget in title.dart.
- reuse: NetImage, Skeleton, friendlyError/ErrorState, monoStyle, scrims, chip/input/button themes, existing page transition.
- no new packages: `http` + `shared_preferences` cover the protocol and persistence.
- new tokens: only `FlickTokens.streamQualityWidth` (60) and `streamMonoStyle` (from Codex).

## Rejected from Codex's proposal
- Restyling the shell NavigationBar (marker above icon, no pill) for Discover: changes every tab's look, out of this feature's scope. Discover uses the existing themed bar.
- Trailing chevrons on stream rows (in the D3 render, not in Codex's written spec): the written spec wins, no trailing affordance; the whole row is the target.
- "|" separators in telemetry (D3 render): use the "·" of the movie render, matching the app's metadata lines.

## Accepted deviations from build-mobile hard rules (pre-existing app)
- The app has no `lib/kit/`, no presets and no theme changer; it went through the earlier UI revamp, not this pipeline. The new screens use no stock dialog, snackbar, picker or spinner at all, so no kit is needed for them. Kit + presets are a separate job.
- `gates.py` already fails on the existing files (theme in lib/theme.dart, Colors.* in older screens). Gate for this feature: zero hits in the new files.
