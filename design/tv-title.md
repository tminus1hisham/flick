# TV Title delta — 2026-10-31

Implements the approved Title direction in design/tv.md and design/tv/title.png. Fixed art/facts pane 264 dp, 24 dp gap, remaining width for independently scrolling episodes/streams. Left edge x144; outer safe insets 48/27. Pushed detail route has Back and Sources controls in the left gutter; Back follows the detail/episode precedence.

Series: season initially focused; episode Select swaps only the right pane; Back restores the same episode and scroll position. Movie: initial loading slot -> first playable stream, or recovery action. Source filters retain focus, provider responses stay independent, and a source retains focus while another inserts/removes rows. Lazy slivers remain in use. Up Next's standalone StreamsScreen entry also uses this TV layout.

State matrix: metadata loading skeleton/slot, metadata offline/error Try again, empty episodes Refresh, no stream sources Add a source, no playable streams Refresh streams/Add a source, per-source loading/Retry, successful stream rows and external services. Late results never steal focus from side actions. TV uses existing focus ring, reveal, tokens and reduced-motion behavior.

Existing stream playback/download APIs, canonical episode IDs, favourites/likes and phone layout are reused. Fixed Retry callbacks returning Futures from setState (also affects phone recovery). No new packages. Cast is omitted because the existing Meta contract does not contain it. At 1.3x and the 900x500 minimum viewport, synopsis lines use available space; no left-pane scrolling.

Applied: ui-ux-pro-max focus visibility/keyboard reachability; apple-design spatial consistency, response and reduced motion; emil-design-eng immediate keyboard feedback and token motion, as already recorded in design/tv.md. Scope excludes Player, Sources, Downloads and Torrent-start TV redesigns.
