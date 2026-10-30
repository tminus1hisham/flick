# Step 03: download addon streams (direct URLs)
files: lib/downloads.dart lib/screens/downloads.dart lib/screens/title.dart lib/playback.dart lib/addons.dart lib/state.dart test/title_test.dart
check:

Today only Jellyfin items download (Downloads.enqueue(JellyfinClient, Item, Quality), called from lib/screens/detail.dart). Add downloads for Stremio addon streams that have a plain `url` (not infoHash, not externalUrl):
1. lib/downloads.dart: `enqueueStream({required String url, Map<String, String> headers, required String title, String? poster, required Playback playback})` on the existing FileDownloader (background_downloader DownloadTask takes `headers`). Store what the Downloads screen and offline playback need in the task's metaData (JSON), the way the Jellyfin path stores its data. Filename from title (+ SxxEyy when season/episode), sanitized, keeping the URL's extension or .mp4.
2. Stream rows in lib/screens/title.dart: a 48 dp download IconButton (tooltip 'Download') on rows whose stream has a url; tapping enqueues and shows a queued state inline on the row (no SnackBar).
3. The Downloads screen lists these next to Jellyfin downloads with the same progress / pause / delete UI; tapping a finished one plays the local file in PlayerScreen as addon playback without headers.
Tests: filename builder (pure function), metaData round trip, download button shown only for url streams.
