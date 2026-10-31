import 'package:shared_preferences/shared_preferences.dart';

import 'addons.dart';
import 'downloads.dart';
import 'saved.dart';

final saved = Saved();

/// Device settings.
final settings = Settings();

/// Not final so widget tests can swap in fakes.
Downloads downloads = Downloads();
Addons addons = Addons();

class Settings {
  late SharedPreferences _prefs;

  Future<void> load() async => _prefs = await SharedPreferences.getInstance();

  /// Up Next counts down and plays the next episode on its own; off, it waits for a tap.
  bool get autoplayNext => _prefs.getBool('autoplayNext') ?? true;
  set autoplayNext(bool on) => _prefs.setBool('autoplayNext', on);
}
