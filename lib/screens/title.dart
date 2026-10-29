import 'package:flutter/material.dart';

import '../addons.dart';

/// D2 Title (movie: streams inline; series: seasons + episodes → D3 Streams). Stub until discover-screens.
class TitleScreen extends StatelessWidget {
  const TitleScreen(this.preview, {super.key});

  /// What Discover already knows, shown while the full meta loads; its poster is the Hero (tag = id).
  final MetaPreview preview;

  @override
  Widget build(BuildContext context) => throw UnimplementedError();
}
