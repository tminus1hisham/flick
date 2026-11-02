import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'addons.dart';
import 'history.dart';

/// Favourites and likes for Discover (addon) titles, kept on this device.
class Saved extends ChangeNotifier {
  late SharedPreferences _prefs;
  List<MetaPreview> favourites = [];
  List<MetaPreview> myList = [];
  Set<String> likes = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    favourites = _read('favourites');
    myList = _read('myList');
    likes = {...?_prefs.getStringList('likes')};
  }

  List<MetaPreview> _read(String key) {
    final result = <MetaPreview>[];
    try {
      for (final value in jsonDecode(_prefs.getString(key) ?? '[]') as List) {
        try {
          final j = value as Map;
          result.add(
        (
          id: j['id'] as String,
          type: j['type'] as String,
          name: j['name'] as String,
          poster: j['poster'] as String?,
          scope: readContentScope(j['scope']), releaseInfo: j['releaseInfo'] as String?,
        ));
        } catch (_) { /* Keep other saved titles when one entry is damaged. */ }
      }
    } catch (_) { /* A damaged collection must not prevent startup. */ }
    return result;
  }

  bool isFavourite(String id, {ContentScope? scope, String type = 'movie'}) =>
      favourites.any((f) => _same(f, id, scope, type));
  bool inMyList(MetaPreview p) => myList.any((f) => _same(f, p.id, p.scope, p.type));
  bool _same(MetaPreview f, String id, ContentScope? scope, String type) =>
      f.id == id && (canonicalVideoId(id) || f.type == type && videoScope(f.id, f.scope) == videoScope(id, scope));
  bool isLiked(String id) => likes.contains(id);

  Future<void> toggleFavourite(MetaPreview p) => _toggle(p, 'favourites');
  Future<void> toggleMyList(MetaPreview p) => _toggle(p, 'myList');

  Future<void> _toggle(MetaPreview p, String key) async {
    final previous = key == 'myList' ? myList : favourites;
    final items = [...previous];
    if (items.any((f) => _same(f, p.id, p.scope, p.type))) {
      items.removeWhere((f) => _same(f, p.id, p.scope, p.type));
    } else {
      items.insert(0, p);
    }
    if (key == 'myList') { myList = items; } else { favourites = items; }
    notifyListeners();
    try {
      if (!await _prefs.setString(key, jsonEncode([
        for (final f in items)
          {'id': f.id, 'type': f.type, 'name': f.name, 'poster': f.poster, 'releaseInfo': f.releaseInfo,
            'scope': writeContentScope(f.scope)},
      ]))) { throw StateError('Could not save $key'); }
    } catch (_) {
      if (identical(key == 'myList' ? myList : favourites, items)) {
        if (key == 'myList') { myList = previous; } else { favourites = previous; }
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> toggleLike(String id) async {
    if (!likes.remove(id)) likes.add(id);
    notifyListeners();
    await _prefs.setStringList('likes', [...likes]);
  }
}
