import 'addons.dart';
import 'downloads.dart';
import 'session.dart';

final session = Session();
final saved = Saved();

/// Not final so widget tests can swap in fakes.
Downloads downloads = Downloads();
Addons addons = Addons();
