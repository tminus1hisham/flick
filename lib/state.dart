import 'package:shared_preferences/shared_preferences.dart';

import 'addons.dart';
import 'downloads.dart';
import 'history.dart';
import 'saved.dart';

final saved = Saved();
final history = ViewingHistory();

/// Device settings.
final settings = Settings();

/// What the app runs on, read once in main(). Tests set its fields.
final device = Device();

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

class Device {
  /// An Android TV (UiModeManager television mode): D-pad focus, 10-foot layout. Width never sets it.
  bool tv = false;
}
