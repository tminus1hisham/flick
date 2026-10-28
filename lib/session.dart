import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jellyfin.dart';

class Session extends ChangeNotifier {
  static const _secure = FlutterSecureStorage();

  late SharedPreferences _prefs;
  late String deviceId;
  JellyfinClient? client;
  bool online = false;

  bool get loggedIn => client?.token != null;

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
  }

  Future<void> login(String server, String username, String password) async {
    final c = JellyfinClient(server: server, deviceId: deviceId);
    await c.login(username, password);
    await _prefs.setString('server', c.server);
    await _prefs.setString('userId', c.userId!);
    await _secure.write(key: 'token', value: c.token);
    client = c;
    online = true;
    notifyListeners();
  }

  Future<void> logout() async {
    await _secure.delete(key: 'token');
    client = null;
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
