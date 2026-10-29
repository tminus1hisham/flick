import 'addons.dart';
import 'downloads.dart';
import 'session.dart';

final session = Session();
final downloads = Downloads();

/// Not final so widget tests can swap in an [Addons] over a mock HTTP client.
Addons addons = Addons();
