# Viewing-history management

This screen exposes the existing local unfinished-video registry. Discover also exposes its checkpoints through Continue Watching.

Discover's history icon opens a route on phone and TV. The screen lists the most recently watched entries first, with title, episode label and position/duration. Remove clears one checkpoint. Clear all first exposes an inline confirmation with Cancel. Back returns to Discover. No media file is deleted.

Reuse Afterglow typography, spacing and the existing TV FocusFrame/reveal policy. Phone targets remain at least 48 dp; TV uses larger text and focus rings. A long history list may scroll. Titles and descriptions wrap at 1.3× text. No new motion, dependencies, settings or popup components.

States: history loads before the app starts, so this route needs no loading state or network access. Empty shows “No unfinished videos”. Success removes entries immediately. Persistence failure stays inline with Retry, including when the in-memory list is empty. Clear confirmation is reversible with Cancel; TV returns focus to Back after a mutation so a removed row never strands remote input.

Validation: widget tests cover entry routing, removal and persisted reload, confirmation/cancel, empty history and TV keyboard navigation at larger text. Existing history tests cover identity, completion and corrupt storage. Native playback behavior is outside this change.

## Continue Watching

Discover shows a horizontal text-card row above its catalog, hidden during search/Favourites and when history is empty. Each card names the title, episode and saved position; spoken labels include the full title/episode even when visible text truncates. TV uses FocusFrame and RevealArea; phone cards use InkWell. All entries remain reachable by horizontal scrolling, with no new motion. The catalog stays keyed when the row appears or disappears.

Selecting a card fetches fresh addon metadata and opens its exact episode's source list, or refreshes Miruro's episode list before opening its existing source picker. Movies use the existing Title screen. No stream URLs or credentials are saved. Loading shows a source-row skeleton with Back; offline/failed/missing episode lookup shows inline Retry and preserves the checkpoint. Completion removes the card at the existing 95% threshold. Eight widget tests cover these paths and TV reveal at larger text; real providers, native playback and physical accessibility remain acceptance work.

## Addon playback choices

Movie and episode stream pages show the existing choice chips for Resume (with saved time) and Start Over, followed by a sentence asking the user to choose a source. Resume is the default. Choices appear only for unfinished videos with stream sources; external service links retain their existing behavior. The selected mode applies to each playable source, while download actions remain independent. TV reuses focus rings and reveal behavior; both layouts use existing tokens and introduce no motion.

Start Over passes zero as the initial player position without deleting history. Cancelling source selection or failing to open leaves the checkpoint intact. Once playback starts, normal checkpointing replaces progress; Retry keeps the current player position and Up Next returns to normal per-video resume behavior. Completion notifications remove the choices. Nine tests cover phone/TV at 1.3× text, remote Right/Select, movie/episode identity, direct/torrent route configuration, cancelling without losing progress, completion updates and override reset for the next video. They do not establish native seek or rendered-video acceptance.
