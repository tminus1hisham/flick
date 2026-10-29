import 'package:flutter_test/flutter_test.dart';

import 'package:flick/screens/player.dart';

void main() {
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
