# Anime build status

Step 01-spike done 2026-10-30 (326e3b1): AniList + Kitsu answer, fixtures in test/fixtures/anime/. AniList 20 -> Kitsu 11.

Next: steps 02-08 still describe the dropped Miruro providers (kiwi/bonk, pipe decode, proxy). Rewrite them for AniList metadata + Stremio addon streams via kitsu:<id>:<ep> + AniList official links before running: pwsh -File tool/anime_build.ps1 -From 2 -To <n>
