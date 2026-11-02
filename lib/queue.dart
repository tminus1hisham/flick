import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'addons.dart';
import 'live.dart';

/// Completion notifications can repeat; neither a failed open nor Retry consumes a queued movie.
class MovieQueueProgress {
  bool _started = false, _advanced = false, _waiting = false;
  bool started() {
    if (_started) return false;
    _started = true;
    return true;
  }
  bool completed({required bool done, required bool stoppedEarly, required bool failed, required bool hasNext,
      bool panelOpen = false}) {
    if (!done || !_started || _advanced || stoppedEarly || failed || !hasNext) return false;
    _advanced = true;
    _waiting = panelOpen;
    return !panelOpen;
  }
  bool release({required bool panelOpen}) {
    if (!_waiting || panelOpen) return false;
    _waiting = false;
    return true;
  }
}

/// A source preference, not a saved playback URL or set of credentials.
class QueuedMovie {
  QueuedMovie({required this.id, required this.title, required this.provider,
    this.poster, this.infoHash, this.fileIdx, this.filename, this.name, this.release, this.group, this.start});
  final String id, title, provider;
  final String? poster, infoHash, filename, name, release, group;
  final int? fileIdx;
  final Duration? start;

  bool sameMovie(String id, String? provider) => this.id == id &&
    (RegExp(r'^tt\d+$').hasMatch(id) || this.provider == provider);

  factory QueuedMovie.fromStream(String id, String title, String? poster, Addon addon, AddonStream stream,
      {Duration? start}) => QueuedMovie(id: id, title: title, poster: poster, provider: addon.base,
    infoHash: stream.infoHash, fileIdx: stream.fileIdx, filename: stream.filename,
    name: stream.name, release: stream.title, group: stream.bingeGroup, start: start);

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'provider': provider, 'poster': poster,
    'infoHash': infoHash, 'fileIdx': fileIdx, 'filename': filename, 'name': name,
    'release': release, 'group': group, 'start': start?.inMilliseconds};

  factory QueuedMovie.fromJson(Map<String, dynamic> j) {
    final item = QueuedMovie(id: j['id'] as String, title: j['title'] as String,
      provider: j['provider'] as String, poster: j['poster'] as String?, infoHash: j['infoHash'] as String?,
      fileIdx: j['fileIdx'] as int?, filename: j['filename'] as String?, name: j['name'] as String?,
      release: j['release'] as String?, group: j['group'] as String?,
      start: j['start'] == null ? null : Duration(milliseconds: j['start'] as int));
    if (item.id.isEmpty || item.title.isEmpty || item.provider.isEmpty ||
        (item.fileIdx != null && item.fileIdx! < 0) || (item.start?.isNegative ?? false)) {
      throw const FormatException('Invalid queued movie');
    }
    return item;
  }

  /// Only a unique match may keep the user's chosen source automatically.
  AddonStream? match(List<AddonStream> streams) {
    final matches = streams.where((s) {
      if (s.externalUrl != null) return false;
      if (infoHash != null) return s.infoHash?.toLowerCase() == infoHash!.toLowerCase() && s.fileIdx == fileIdx;
      if (s.url == null || s.infoHash != null || s.bingeGroup != group) return false;
      if (filename != null && filename!.isNotEmpty) return s.filename == filename && s.name == name;
      return (name?.isNotEmpty ?? false) && (release?.isNotEmpty ?? false) && s.name == name && s.title == release;
    }).toList();
    return matches.length == 1 ? matches.single : null;
  }
}

class MovieQueue extends ChangeNotifier {
  final _items = <QueuedMovie>[];
  SharedPreferences? _prefs;
  Future<void>? _pending;
  String? error;
  List<QueuedMovie> get items => List.unmodifiable(_items);
  bool contains(String id, {String? provider}) => _items.any((m) =>
    provider == null ? m.id == id : m.sameMovie(id, provider));

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _items.clear();
    try {
      for (final row in jsonDecode(_prefs!.getString('movieQueue') ?? '[]') as List) {
        try {
          final item = QueuedMovie.fromJson(Map<String, dynamic>.from(row as Map));
          if (!contains(item.id, provider: item.provider)) _items.add(item);
        } catch (_) { /* One damaged row must not lose the rest of the queue. */ }
      }
    } catch (_) { /* A damaged registry must not block startup. */ }
    notifyListeners();
  }

  Future<bool> add(QueuedMovie item) async {
    if (contains(item.id, provider: item.provider)) return false;
    _items.add(item);
    await save();
    return true;
  }

  Future<void> remove(QueuedMovie item) async { _items.remove(item); await save(); }
  Future<void> clear() async { _items.clear(); await save(); }
  Future<void> move(QueuedMovie item, int delta) async {
    final from = _items.indexOf(item), to = _items.indexOf(item) + delta;
    if (from < 0 || to < 0 || to >= _items.length) return;
    _items.removeAt(from); _items.insert(to, item);
    await save();
  }

  Future<void> save() {
    notifyListeners();
    // Serialize writes, and capture the current registry when each write actually runs.
    Future<void> write() async {
      try {
        _prefs ??= await SharedPreferences.getInstance();
        if (!await persist(jsonEncode(_items.map((m) => m.toJson()).toList()))) {
          throw StateError('Queue save failed');
        }
        error = null;
      } catch (_) { error = 'Could not save the playback queue. Retry before closing the app.'; }
      notifyListeners();
    }
    final operation = _pending?.then((_) => write()) ?? write();
    _pending = operation;
    return operation.whenComplete(() { if (identical(_pending, operation)) _pending = null; });
  }

  @protected
  Future<bool> persist(String value) => _prefs!.setString('movieQueue', value);
}

class LiveQueue extends ChangeNotifier {
  final _items = <LiveEvent>[];
  List<LiveEvent> get items => List.unmodifiable(_items);
  bool contains(LiveEvent event) => _items.any((e) => e.id == event.id && e.sport == event.sport);
  bool add(LiveEvent event) {
    if (contains(event)) return false;
    _items.add(event); notifyListeners(); return true;
  }
  void remove(LiveEvent event) { _items.removeWhere((e) => e.id == event.id && e.sport == event.sport); notifyListeners(); }
  void move(LiveEvent event, int delta) {
    final from = _items.indexOf(event), to = _items.indexOf(event) + delta;
    if (from < 0 || to < 0 || to >= _items.length) return;
    _items.removeAt(from); _items.insert(to, event); notifyListeners();
  }
}
