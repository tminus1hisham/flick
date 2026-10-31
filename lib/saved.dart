import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'addons.dart';

/// Favourites and likes for Discover (addon) titles, kept on this device.
class Saved extends ChangeNotifier {
  late SharedPreferences _prefs;
  List<MetaPreview> favourites = [];
  Set<String> likes = {};

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    favourites = [
      for (final j in jsonDecode(_prefs.getString('favourites') ?? '[]') as List)
        (
          id: j['id'] as String,
          type: j['type'] as String,
          name: j['name'] as String,
          poster: j['poster'] as String?,
          releaseInfo: j['releaseInfo'] as String?,
        ),
    ];
    likes = {...?_prefs.getStringList('likes')};
  }

  bool isFavourite(String id) => favourites.any((f) => f.id == id);
  bool isLiked(String id) => likes.contains(id);

  Future<void> toggleFavourite(MetaPreview p) async {
    isFavourite(p.id) ? favourites.removeWhere((f) => f.id == p.id) : favourites.insert(0, p);
    notifyListeners();
    await _prefs.setString('favourites', jsonEncode([
      for (final f in favourites)
        {'id': f.id, 'type': f.type, 'name': f.name, 'poster': f.poster, 'releaseInfo': f.releaseInfo},
    ]));
  }

  Future<void> toggleLike(String id) async {
    if (!likes.remove(id)) likes.add(id);
    notifyListeners();
    await _prefs.setStringList('likes', [...likes]);
  }
}
