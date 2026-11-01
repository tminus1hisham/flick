import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flick/screens/player.dart';
import 'package:flick/state.dart';

Caption caption(String id, String language, {String? url}) => (
  track: SubtitleTrack(id, language, language), url: url,
  lang: subtitleLanguage(language), label: id, detail: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('language preferences default to existing behavior and persist independently', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = Settings();
    await settings.load();
    expect(settings.audioLanguage, isNull);
    expect(settings.subtitleLanguage, isNull);
    await settings.saveAudioLanguage(subtitleLanguage('jpn'));
    await settings.saveSubtitleLanguage(subtitleLanguage('eng'));
    final restored = Settings();
    await restored.load();
    expect(restored.audioLanguage, 'ja');
    expect(restored.subtitleLanguage, 'en');
    await restored.saveSubtitleLanguage('off');
    final off = Settings();
    await off.load();
    expect(off.subtitleLanguage, 'off');
    expect(off.audioLanguage, 'ja');
    await off.saveSubtitleLanguage('fr');
    final enabled = Settings();
    await enabled.load();
    expect(enabled.subtitleLanguage, 'fr');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'audioLanguage', 'subtitleLanguage'});
  });

  group('audio preferences', () {
    final english = AudioTrack('1', 'English', 'eng');
    final japanese = AudioTrack('2', 'Japanese', 'ja-JP');
    test('matches normalized language across new track IDs and offline tracks', () {
      expect(preferredAudioTrack([english, japanese], 'jpn'), japanese);
      final next = AudioTrack('97', 'Japanese next episode', 'jpn');
      expect(preferredAudioTrack([english, next], 'ja'), next);
    });
    test('missing language or no preference leaves the engine fallback alone', () {
      expect(preferredAudioTrack([english], 'fr'), isNull);
      expect(preferredAudioTrack([english], null), isNull);
      expect(preferredAudioTrack([AudioTrack.auto(), AudioTrack.no()], 'en'), isNull);
    });
    test('the current video choice wins on Retry, including an unknown language', () {
      expect(preferredAudioTrack([english, japanese], 'en', choice: japanese), japanese);
      final unknown = AudioTrack('3', 'Commentary', null);
      expect(preferredAudioTrack([english, unknown], 'en', choice: unknown), unknown);
      expect(preferredAudioTrack([english], 'en', choice: japanese), isNull);
      final commentary = AudioTrack('3', 'English commentary', 'eng');
      expect(preferredAudioTrack([english, commentary], 'en', choice: commentary), commentary);
    });
  });

  group('subtitle preferences', () {
    final embedded = caption('1', 'eng');
    final addon = caption('https://subs.test/addon', 'eng', url: 'https://subs.test/addon');
    final stream = caption('https://subs.test/stream', 'en-US', url: 'https://subs.test/stream');
    Caption? pick(List<Caption> tracks, {String? preference = 'en', Caption? choice,
      String? audio = 'en', String selected = '1'}) => preferredCaption(tracks,
        preference: preference, choice: choice, deviceLanguage: 'en-US',
        audioLanguage: audio, selectedId: selected, streamUrls: {stream.url!});

    test('Off applies with no subtitle catalogue and despite engine-selected tracks', () {
      expect(pick([], preference: 'off')!.track.id, 'no');
      expect(pick([], preference: 'off')!.lang, 'en');
      expect(pick([embedded], preference: 'off')!.track.id, 'no');
    });
    test('an explicit language overrides same-language audio and engine selection', () {
      expect(pick([embedded]), embedded);
      expect(pick([caption('9', 'fra')], preference: 'fr')!.track.id, '9');
    });
    test('default keeps device/audio heuristic and existing engine selection', () {
      expect(pick([embedded], preference: null), isNull);
      expect(pick([embedded], preference: null, audio: 'ja'), isNull);
      expect(pick([embedded], preference: null, audio: 'ja', selected: 'no'), embedded);
    });
    test('stream files precede addon files, with embedded-only offline fallback', () {
      expect(pick([embedded, addon, stream]), stream);
      expect(pick([embedded, addon]), addon);
      expect(pick([embedded]), embedded);
    });
    test('a missing language safely preserves the current engine choice', () {
      expect(pick([embedded], preference: 'de'), isNull);
      expect(pick([], preference: 'en'), isNull);
    });
    test('Retry uses a manual external file with its fresh mpv ID', () {
      final reloaded = caption('new-id', 'eng', url: addon.url);
      expect(pick([reloaded, stream], preference: 'fr', choice: addon), reloaded);
    });
    test('manual embedded and Off choices win over stored preferences on Retry', () {
      expect(pick([embedded, stream], preference: 'off', choice: embedded), embedded);
      final off = (track: SubtitleTrack.no(), url: null, lang: 'en', label: 'Off', detail: '');
      expect(pick([embedded], choice: off)!.track.id, 'no');
    });
  });

  test('device languages match Stremio aliases and region variants', () {
    for (final (code, expected) in [
      ('eng', 'en'),
      ('spa', 'es'),
      ('fre', 'fr'),
      ('fra', 'fr'),
      ('ger', 'de'),
      ('deu', 'de'),
      ('dut', 'nl'),
      ('nld', 'nl'),
      ('por', 'pt'),
      ('ita', 'it'),
      ('pol', 'pl'),
      ('rus', 'ru'),
      ('tur', 'tr'),
      ('ara', 'ar'),
      ('swa', 'sw'),
      ('EN-us', 'en'),
      ('pt_BR', 'pt'),
      ('unknown', 'unknown'),
    ]) {
      expect(subtitleLanguage(code), expected);
    }
    expect(subtitleLanguageName('eng'), 'English');
    expect(subtitleLanguageName('es'), 'Spanish');
    expect(subtitleLanguageName('fr-FR'), 'French');
    expect(subtitleLanguageName(''), 'Unknown language');
  });
}
