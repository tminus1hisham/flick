import 'package:flutter/widgets.dart';

import 'addons.dart';

/// What the player needs to name a title and find its subtitles.
typedef Playback = ({String title, String? subtitle, String type, String videoId, int? season, int? episode});

/// Plays [s]: url → player, infoHash → torrent start (fileIdx, else a guessed file),
/// externalUrl → the service's app or site. Returns when the user is back on the stream list.
Future<void> play(BuildContext context, AddonStream s, Playback p) => throw UnimplementedError();
