import 'addons.dart';
import 'downloads.dart';
import 'saved.dart';

final saved = Saved();
final downloads = Downloads();

/// Not final so widget tests can swap in a fake.
Addons addons = Addons();
