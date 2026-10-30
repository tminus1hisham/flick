# Step 02: data layer `lib/anime.dart`
files: tool/anime_spike.dart lib/addons.dart lib/state.dart test/addons_test.dart test/fixtures/anime/raw_episodes.txt test/fixtures/anime/episodes_20.json test/fixtures/anime/sources_kiwi.json test/fixtures/anime/sources_bonk.json test/fixtures/anime/sources_pewe.json test/fixtures/anime/sources_bun.json test/fixtures/anime/info_20.json

Build `lib/anime.dart` per the plan's "Data layer" section, reusing the encode/decode you wrote in tool/anime_spike.dart (the fixtures show what really comes back; trust them over the reference code). Shape (adjust field names only if the fixtures force it):

```dart
enum AnimeError { blocked, unreachable, changed }   // 403/444 · network/timeout · decode or shape failure
class AnimeException implements Exception { final AnimeError error; ... }
typedef Skip = ({Duration start, Duration end, String kind}); // kind: 'intro' | 'outro'
typedef AnimeCard = ({int id, String title, String? poster, String? format, int? episodes, String? status, int? score, ({int episode, DateTime at})? next});
typedef AnimeInfo = ({AnimeCard card, String? banner, String? description, List<String> genres, String? season, int? year});
typedef AnimeEpisode = ({int number, String? title, String? image, bool filler, Map<String, String> ids}); // provider -> episode id
typedef AnimeSource = ({String url, Map<String, String> headers, List<Subtitle> subtitles, List<Skip> skips, String provider, String lang, String? quality});
enum AnimeCatalog { season, airing, trending, popular, upcoming }
class Anime {
  Anime({http.Client? client, DateTime Function()? now});
  Future<List<AnimeCard>> catalog(AnimeCatalog c, {int page = 1, String? genre});
  Future<List<AnimeCard>> search(String q, {int page = 1});
  Future<AnimeInfo> info(int id);
  Future<({List<AnimeEpisode> sub, List<AnimeEpisode> dub})> episodes(int id);
  Future<AnimeSource> resolve(int id, int number, String lang, {String? provider}); // preferred provider, then ONE fallback
  List<String> providersFor(AnimeEpisode e);   // allow-list order, decoys (bee, ally) dropped
  Future<String> lang(int id); Future<void> setLang(int id, String lang); // 'sub' | 'dub', shared_preferences
}
```
- `Subtitle` is the existing record from lib/addons.dart; reuse it.
- Pure, top-level and tested: `encodePipe`, `decodePipe(String body, String? obfuscated)`, `decodePru`/`encodePru`, `parseEpisodes`, `parseSource`, `skipsFrom`. Headers per stream come from its own referer (never Miruro's for a CDN that names another referer).
- Caches: episodes 5 min, sources 10 min, AniList lists in memory; concurrent identical requests share one Future.
- In lib/state.dart add `Anime anime = Anime();` (not final, like `addons`, so tests can swap it).
- `test/anime_test.dart`: decode the raw fixture; parse episodes and sources fixtures; pru round trip; provider order + decoy drop; resolve falls back exactly once (MockClient from package:http/testing.dart); 403 -> blocked, garbage -> changed, SocketException -> unreachable; lang persistence (SharedPreferences.setMockInitialValues). Missing fixture files: skip only those tests with a clear reason.
