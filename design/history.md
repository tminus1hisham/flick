# Viewing-history management

This slice exposes the existing local unfinished-video registry. Continue Watching, source resolution and explicit playback choices remain separate backlog work.

Discover's history icon opens a route on phone and TV. The screen lists the most recently watched entries first, with title, episode label and position/duration. Remove clears one checkpoint. Clear all first exposes an inline confirmation with Cancel. Back returns to Discover. No media file is deleted.

Reuse Afterglow typography, spacing and the existing TV FocusFrame/reveal policy. Phone targets remain at least 48 dp; TV uses larger text and focus rings. A long history list may scroll. Titles and descriptions wrap at 1.3× text. No new motion, dependencies, settings or popup components.

States: history loads before the app starts, so this route needs no loading state or network access. Empty shows “No unfinished videos”. Success removes entries immediately. Persistence failure stays inline with Retry, including when the in-memory list is empty. Clear confirmation is reversible with Cancel; TV returns focus to Back after a mutation so a removed row never strands remote input.

Validation: widget tests cover entry routing, removal and persisted reload, confirmation/cancel, empty history and TV keyboard navigation at larger text. Existing history tests cover identity, completion and corrupt storage. Native playback behavior is outside this change.
