import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'addons.dart';
import 'jellyfin.dart';

class Session extends ChangeNotifier {
  static const _secure = FlutterSecureStorage();

  late SharedPreferences _prefs;
  late String deviceId;
  JellyfinClient? client;
  bool online = false;

  /// Past the first-launch Login: signed in once, or chose to continue as a guest.
  bool onboarded = false;

  bool get loggedIn => client?.token != null;

  /// Up Next counts down and plays the next episode on its own; off, it waits for a tap.
  bool get autoplayNext => _prefs.getBool('autoplayNext') ?? true;
  set autoplayNext(bool on) => _prefs.setBool('autoplayNext', on);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    deviceId = _prefs.getString('deviceId') ?? _newDeviceId();
    await _prefs.setString('deviceId', deviceId);
    final server = _prefs.getString('server');
    final token = await _secure.read(key: 'token');
    if (server != null && token != null) {
      client = JellyfinClient(
          server: server, deviceId: deviceId, token: token, userId: _prefs.getString('userId'));
      online = await client!.reachable();
    }
    // Installs from before guest mode were signed in, so they never see the guest link.
    onboarded = _prefs.getBool('onboarded') ?? loggedIn;
  }

  Future<void> continueAsGuest() async {
    await _prefs.setBool('onboarded', true);
    onboarded = true;
    notifyListeners();
  }

  Future<void> login(String server, String username, String password) async {
    final c = JellyfinClient(server: server, deviceId: deviceId);
    await c.login(username, password);
    await _prefs.setString('server', c.server);
    await _prefs.setString('userId', c.userId!);
    await _secure.write(key: 'token', value: c.token);
    await _prefs.setBool('onboarded', true);
    onboarded = true;
    client = c;
    online = true;
    notifyListeners();
  }

  /// Leaves [onboarded] set, so signing out lands in the guest shell, not on Login.
  Future<void> logout() async {
    await _secure.delete(key: 'token');
    client = null;
    // Downloaded files keep playing for a guest; online would send them to the absent server.
    online = false;
    notifyListeners();
  }

  Future<void> recheck() async {
    online = await client?.reachable() ?? false;
    notifyListeners();
  }

  static String _newDeviceId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Favourites and likes for Discover (addon) titles, kept on this device.
// ponytail: one list per device, not per account (Flick has one user); key by server+userId if that changes.
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
