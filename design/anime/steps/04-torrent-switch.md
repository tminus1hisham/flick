# Step 04: "Torrent streaming" switch
files: lib/addons.dart lib/screens/sources.dart lib/main.dart lib/playback.dart lib/screens/title.dart lib/screens/torrent.dart test/sources_test.dart test/title_test.dart test/addons_test.dart

Per the plan's "Hiding torrents" section.
- Persist the setting where the bundled-addon switches live (lib/addons.dart), default on, exposed as a `ValueListenable<bool>` (or the existing notifier pattern there) so the shell rebuilds.
- Sources screen: a switch row in the same style as the bundled rows. Title `Torrent streaming`, supporting line `Use peer-to-peer sources and show magnet actions.`
- When off: `MagnetButton` hidden in the shell AppBar and the OfflineShell (lib/main.dart); streams with an `infoHash` or a `magnet:` URL removed from stream lists (a pure `bool isTorrentStream(AddonStream s)` + filter, tested); `play()` refuses to open TorrentScreen for them (defensive; they shouldn't be listed). Existing downloads untouched. A stream group that becomes empty shows the existing empty-group state, not an error.
- Tests: persistence, filter, the Sources switch toggles it, title stream list hides torrent rows when off.
