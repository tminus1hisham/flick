import 'addons.dart';
import 'downloads.dart';
import 'session.dart';

final session = Session();
final downloads = Downloads();
final saved = Saved();

/// Not final so widget tests can swap in a fake.
Addons addons = Addons();
