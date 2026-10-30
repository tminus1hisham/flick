# Step 01: source spike and fixtures (gate for everything after it)
files: lib/addons.dart pubspec.yaml analysis_options.yaml
check: dart run tool/anime_spike.dart

DIRECTION CHANGE (overrides design/anime.md): Miruro is dropped (Cloudflare blocks it; no bypasses of any kind). Anime = AniList public GraphQL (https://graphql.anilist.co, no key) for all metadata, and video comes only from:
(a) the user's installed Stremio addons (Flick's existing addon client, lib/addons.dart) — anime addons use `kitsu:<kitsuId>` (movie) / `kitsu:<kitsuId>:<episode>` ids, so we need AniList -> Kitsu id mapping;
(b) official links from AniList `streamingEpisodes` / `externalLinks`, opened with the existing openExternal handoff.

Write `tool/anime_spike.dart`, a standalone Dart CLI (dart:io, dart:convert, package:http; no Flutter imports; `stdout.writeln`, not `print`) that records fixtures and proves the public endpoints answer:
1. AniList `Media(id: 20)`: id, idMal, title{romaji english native}, coverImage{large extraLarge}, bannerImage, format, status, episodes, duration, averageScore, genres, season, seasonYear, description, nextAiringEpisode{episode airingAt}, streamingEpisodes{title thumbnail url site}, externalLinks{site url type}. Save to `test/fixtures/anime/info_20.json`.
2. AniList `Page(perPage: 6){ media(season: <current>, seasonYear: <current>, type: ANIME, sort: POPULARITY_DESC) {...card fields} }` -> `test/fixtures/anime/season.json`, and an `airingSchedule` page for today -> `airing.json`.
3. Kitsu public JSON:API mapping for AniList 20: `https://kitsu.io/api/edge/mappings?filter[externalSite]=anilist/anime&filter[externalId]=20&include=item` -> `kitsu_mapping_20.json` (print the Kitsu anime id). Then `https://kitsu.io/api/edge/anime/<kitsuId>/episodes?page[limit]=20` -> `kitsu_episodes.json`. If the mapping endpoint shape differs, inspect the JSON and adapt; if Kitsu is unreachable say so.
4. Print one `ok`/`FAIL` line per check. `exit(0)` only when 1 and 3 both succeed and a Kitsu anime id was found; else `exit(1)`.
Keep it under ~200 lines; must pass `flutter analyze`.
