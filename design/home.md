# Discover home — approved Netflix-style direction

Approved 2026-11-03: replace the landing page on phone and Android TV, retain Browse/search, rotate movie picks, inline muted previews, separate My List and Favourites, and use existing catalog popularity ordering.

## Experience and states

The vertically scrolling home contains the featured carousel, existing Continue Watching, nonempty My List and Favourites, numbered Popular Movies (at most ten), Popular Series, and other enabled movie/series catalogs with source labels. These are provider rankings, not live, regional, or audience-measured Top 10 claims. Browse retains type/genre filters, submitted search and pagination. See all opens the existing catalog feed.

The feature draws up to five distinct shuffled movies from the first bundled Popular Movies page, stable for the lifetime of this home session. Only those candidates request full metadata. Each catalog has its own skeleton, empty message and connection/source failure with Retry; failed remote data does not remove personal rows. Metadata or trailer failures retain artwork/title actions. Missing artwork uses the house skeleton. Saving failures appear beside actions and retain/revert the previous collection as appropriate.

All colours, typography, focus/reveal, corner radii and transitions reuse Afterglow and the focus kit. Actions wrap at large text and meet the 48dp target. Phone fits a 360×640 viewport by scrolling. TV rows use mounted horizontal cells so remote traversal can reveal the next poster. New row cards have no Hero tags, avoiding collisions when one title appears several times.

## Preview lifecycle

Artwork rotates after ten seconds; a playing trailer advances on completion. Previous/Next and Pause/Resume rotation are explicit actions. Focus, hover and pointer interaction independently suspend rotation. Reduced motion disables automatic rotation and previews. Autoplay previews is a persisted home control, on by default; every new preview starts muted.

Only one preview platform view exists. Tab activity, app lifecycle, route coverage and the actual video area's intersection with the scroll viewport govern mounting. Opening a title, Browse, history, queue or Continue Watching suspends previews. Returning restores the home and its scroll position. The native Activity also pauses preview WebViews on pause and destroys them on teardown. Previews never use movie playback, history, PiP or Up Next.

The Android platform view uses the existing WebKit dependency. YouTube uses its official IFrame API, visible controls/branding and a package-derived HTTPS document origin/referrer; title actions sit outside the video. Player height is at least 200dp. Validated direct HTTP(S) trailers use an HTML video element; HTTP video gets an HTTP document base to avoid mixed-content blocking. No scraping, stream extraction or JavaScript interface exposes app capabilities to trailers. A startup deadline, blocked autoplay or playback error restores artwork. Watch Trailer opens the external link; launch failure shows the URL inline.

## Data and compatibility

`Meta.trailers` contains validated `Trailer` records parsed from both `trailers` and `trailerStreams`. Existing metadata fakes include the field. Catalog pages are fetched lazily and shared between the banner and movie row; duplicates are removed within a row using content identity. Source changes invalidate the home session and cached pages.

`Saved.myList`, `inMyList` and `toggleMyList` persist a separate `myList` preference. Existing favourites/likes remain in their original preferences. My List and favourite comparisons retain custom catalog ownership while canonical IDs remain shared. Legacy unscoped custom entries remain unscoped. Saved-title likes and movie-queue deduplication remain backlog item 9 and are outside this change.

## Device acceptance still required

No connected device/emulator was available during implementation. Native compilation and widget tests cannot establish decoded video, YouTube autoplay availability, TV WebView remote navigation, accessibility or background audio behaviour on hardware. Verify phone/TV mute and controls, autoplay blocked/region-restricted/unavailable WebView fallback, direct HTTP(S) playback, scrolling offscreen, tab/route changes, background/resume and repeated carousel changes without leaked audio/views. Use TalkBack, physical remote and 1.3× text. Obtain permission before controlling the user's physical device or using paid mobile data.
