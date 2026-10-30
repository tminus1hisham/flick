# Step 01: spike CLI and fixtures (gate for everything after it)
files: lib/addons.dart pubspec.yaml analysis_options.yaml
check: dart run tool/anime_spike.dart

Write `tool/anime_spike.dart`, a standalone Dart CLI (dart:io, dart:convert, package:http only; no Flutter imports) that proves the Miruro pipe works from this machine (a residential IP, Dart's own TLS) and records fixtures for the tests in later steps. Port the request encoding, the header set, mirror rotation and the `x-obfuscated` decoding (plain, scheme 1, scheme 2 XOR with the key) from ref/src_helpers_pipe.js. Use the paths and queries ref/src_routes_apiRoutes.js uses for episodes and sources.

It must:
1. Fetch episodes for AniList id 20 (Naruto). Save the raw HTTP body and its `x-obfuscated` header to `test/fixtures/anime/raw_episodes.txt` (first line = header value or `none`, rest = body), and the decoded JSON, pretty-printed, to `test/fixtures/anime/episodes_20.json`.
2. For the first sub episode of each available provider among kiwi, bonk, pewe, bun (in that order; stop after 2 that succeed), fetch sources and save decoded JSON to `test/fixtures/anime/sources_<provider>.json`.
3. For the first stream URL found, GET it with the referer from the source (else `https://www.miruro.to/`) and Chrome User-Agent; save the status line and the first 2 KB to `test/fixtures/anime/playlist_<provider>.txt`. If the URL is a pru.ultracloud.cc URL, also decode it (ref/api_proxy.js) and print the inner URL and referer.
4. Fetch AniList GraphQL `Media(id: 20)` (title, coverImage, bannerImage, format, status, episodes, averageScore, nextAiringEpisode, genres, season, seasonYear, description) and save to `test/fixtures/anime/info_20.json`.
5. Print one summary line per check (`ok`/`FAIL` + reason, e.g. HTTP 403 = Cloudflare block). Use `stdout.writeln` (no `print`, it trips `avoid_print`).
6. `exit(0)` only if a playlist fixture starts with `#EXTM3U`; otherwise `exit(1)`. If every mirror returns 403/444, say "blocked by Cloudflare" and exit 1 — do not try ScraperAPI/FlareSolverr.

Keep it under ~250 lines. This file is throwaway tooling but must pass `flutter analyze`.
