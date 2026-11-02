import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool canonicalVideoId(String id) => RegExp(r'^(tt\d+(?::\d+:\d+)?|kitsu:\d+(?::\d+)?|anilist:\d+:\d+)$').hasMatch(id);

typedef ContentScope = ({String provider, String titleId});
ContentScope? readContentScope(Object? value) => value == null ? null :
    (provider: (value as Map)['provider'] as String, titleId: value['titleId'] as String);
Map<String, String>? writeContentScope(ContentScope? scope) => scope == null ? null :
    {'provider': scope.provider, 'titleId': scope.titleId};
ContentScope? videoScope(String id, ContentScope? scope) => canonicalVideoId(id) ? null : scope;
bool _validId(String id, ContentScope? scope) => canonicalVideoId(id) ||
    id.isNotEmpty && scope != null && scope.provider.isNotEmpty && scope.titleId.isNotEmpty &&
    !id.contains('://');

/// mpv reports zero during open/close as well as when the user seeks to the start.
Duration? watchPosition(Duration reported, {required bool started, required bool opening, required bool completed}) {
  if (reported.isNegative || reported == Duration.zero && (!started || opening || completed)) return null;
  return reported;
}

/// Only content identity and progress are saved, never stream URLs or request headers.
class WatchProgress {
  const WatchProgress({required this.type, required this.videoId, required this.title,
    this.subtitle, this.poster, this.scope, required this.position, required this.duration});

  final String type, videoId, title;
  final String? subtitle, poster;
  final Duration position, duration;
  final ContentScope? scope;

  (String, String, ContentScope?) get key => (type, videoId, videoScope(videoId, scope));
  bool get finished => duration > Duration.zero && position.inMilliseconds >= duration.inMilliseconds * 0.95;

  Map<String, Object?> toJson() => {
    'type': type, 'videoId': videoId, 'title': title, 'subtitle': subtitle, 'poster': poster,
    'position': position.inMilliseconds, 'duration': duration.inMilliseconds,
    if (videoScope(videoId, scope) != null) 'scope': writeContentScope(scope),
  };

  factory WatchProgress.fromJson(Map<String, dynamic> j) {
    final progress = WatchProgress(
      type: j['type'] as String, videoId: j['videoId'] as String, title: j['title'] as String,
      subtitle: j['subtitle'] as String?, poster: j['poster'] as String?,
      scope: readContentScope(j['scope']),
      position: Duration(milliseconds: j['position'] as int),
      duration: Duration(milliseconds: j['duration'] as int),
    );
    if (progress.type.isEmpty || !_validId(progress.videoId, progress.scope) || progress.position <= Duration.zero ||
        progress.duration.isNegative || progress.finished) {
      throw const FormatException('Invalid viewing progress');
    }
    return progress;
  }
}

/// Canonical IDs are shared across sources; custom IDs include their owning provider and parent title.
/// Downloads retain that same identity, independently of the selected stream.
class ViewingHistory extends ChangeNotifier {
  SharedPreferences? _prefs;
  final _entries = <(String, String, ContentScope?), WatchProgress>{};

  List<WatchProgress> get entries => _entries.values.toList().reversed.toList();
  Duration position(String type, String videoId, {ContentScope? scope}) =>
      _entries[(type, videoId, videoScope(videoId, scope))]?.position ?? Duration.zero;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _entries.clear();
    try {
      final stored = jsonDecode(_prefs!.getString('viewingHistory') ?? '[]') as List;
      for (final value in stored) {
        try {
          final progress = WatchProgress.fromJson(value as Map<String, dynamic>);
          _entries[progress.key] = progress;
        } catch (_) { /* A damaged entry must not discard other titles or prevent startup. */ }
      }
    } catch (_) { /* A damaged registry must not prevent startup. */ }
    notifyListeners();
  }

  Future<void> save(WatchProgress progress) async {
    if (progress.type.isEmpty || !_validId(progress.videoId, progress.scope) || progress.position.isNegative || progress.duration.isNegative) return;
    final previous = _entries.remove(progress.key);
    if (progress.position > Duration.zero && !progress.finished) {
      _entries[progress.key] = progress;
    } else if (previous == null) {
      return;
    }
    // shortcut: retain the most recent 100 unfinished videos; revisit for a full history browser.
    while (_entries.length > 100) { _entries.remove(_entries.keys.first); }
    await _persist();
  }

  Future<void> remove(String type, String videoId, {ContentScope? scope}) async {
    _entries.remove((type, videoId, videoScope(videoId, scope)));
    // A retry must write again even if a failed write already removed the in-memory entry.
    await _persist();
  }

  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  Future<void> _persist() async {
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    if (!await _prefs!.setString('viewingHistory', jsonEncode([for (final p in _entries.values) p.toJson()]))) {
      throw StateError('Could not save viewing progress');
    }
  }
}
