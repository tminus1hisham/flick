import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// shortcut: custom addon IDs need an owning-provider scope before they can safely resume.
bool _canonicalId(String id) => RegExp(r'^(tt\d+(?::\d+:\d+)?|kitsu:\d+(?::\d+)?|anilist:\d+:\d+)$').hasMatch(id);

/// mpv reports zero during open/close as well as when the user seeks to the start.
Duration? watchPosition(Duration reported, {required bool started, required bool opening, required bool completed}) {
  if (reported.isNegative || reported == Duration.zero && (!started || opening || completed)) return null;
  return reported;
}

/// Only content identity and progress are saved, never stream URLs or request headers.
class WatchProgress {
  const WatchProgress({required this.type, required this.videoId, required this.title,
    this.subtitle, this.poster, required this.position, required this.duration});

  final String type, videoId, title;
  final String? subtitle, poster;
  final Duration position, duration;

  (String, String) get key => (type, videoId);
  bool get finished => duration > Duration.zero && position.inMilliseconds >= duration.inMilliseconds * 0.95;

  Map<String, Object?> toJson() => {
    'type': type, 'videoId': videoId, 'title': title, 'subtitle': subtitle, 'poster': poster,
    'position': position.inMilliseconds, 'duration': duration.inMilliseconds,
  };

  factory WatchProgress.fromJson(Map<String, dynamic> j) {
    final progress = WatchProgress(
      type: j['type'] as String, videoId: j['videoId'] as String, title: j['title'] as String,
      subtitle: j['subtitle'] as String?, poster: j['poster'] as String?,
      position: Duration(milliseconds: j['position'] as int),
      duration: Duration(milliseconds: j['duration'] as int),
    );
    if (progress.type.isEmpty || !_canonicalId(progress.videoId) || progress.position <= Duration.zero ||
        progress.duration.isNegative || progress.finished) {
      throw const FormatException('Invalid viewing progress');
    }
    return progress;
  }
}

/// Canonical Stremio IDs include their namespace (tt…, kitsu:…); Miruro uses anilist:….
/// Sharing that identity with downloads also lets a different source resume the same episode.
class ViewingHistory extends ChangeNotifier {
  SharedPreferences? _prefs;
  final _entries = <(String, String), WatchProgress>{};

  List<WatchProgress> get entries => _entries.values.toList().reversed.toList();
  Duration position(String type, String videoId) => _entries[(type, videoId)]?.position ?? Duration.zero;

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
    if (progress.type.isEmpty || !_canonicalId(progress.videoId) || progress.position.isNegative || progress.duration.isNegative) return;
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

  Future<void> remove(String type, String videoId) async {
    if (_entries.remove((type, videoId)) != null) await _persist();
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
