# Step 04: download torrent streams
files: android/app/src/main/kotlin/dev/local/flick/Torrents.kt lib/torrent.dart lib/downloads.dart lib/screens/downloads.dart lib/screens/title.dart lib/screens/torrent.dart test/torrent_test.dart
check: flutter build apk --debug

Torrent streams (infoHash, incl. Torrentio anime season packs) download through the existing libtorrent4j engine, not background_downloader.
1. Torrents.kt: new channel method `keep` (id, file index): mark the entry as a download so `release` and the 60 s ENGINE_TIMEOUT never remove it; set file priorities so only the chosen file downloads (others IGNORE); when the file is complete, pause the torrent and report `done` in `status`. Kept downloads live under the app files dir `downloads/torrents/<infoHash>/`, never the streaming cache dir, so release/cleanup can't delete them. `remove` deletes a kept download's data. Every TorrentHandle call stays on the `ctl` executor under synchronized(e) after the `alive` check, like the existing code. Persist kept downloads (infoHash, magnet, file index, dir, title JSON) in a small JSON file and re-add them on app start via a `resumeKept` method so they survive restarts.
2. lib/torrent.dart: TorrentEngine.keep / resumeKept wrappers. lib/downloads.dart: torrent downloads appear in the same list the Downloads screen renders (a small adapter type); poll status every 2 s only while a torrent download is active.
3. Title stream rows: the download IconButton from step 03 also shows for infoHash streams; tapping picks the file the way TorrentScreen does (fileIdx, else guessFile when sure, else the TorrentScreen file list in a 'Download' mode) and calls keep.
4. Finished torrent downloads play the local file like step 03's.
Tests: the pure Dart parts (status -> progress/done mapping, persistence JSON round trip). The Kotlin compiles via the check.
