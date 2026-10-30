import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'anime.dart';

class MiruroBrowser {
  static const _channel = MethodChannel('flick/miruro');
  String? _pending;

  Future<http.Response> request(Uri uri) async {
    if (_pending != null) throw const AnimeException(AnimeError.unreachable);
    if (uri.scheme != 'https' ||
        uri.hasFragment ||
        !miruroOrigins.contains(uri.origin) ||
        !(uri.path == '/api/v1/anime' ||
            RegExp(
              r'^/api/v1/anime/[A-Za-z0-9_-]{1,100}/episodes(?:/[1-9][0-9]*/play)?$',
            ).hasMatch(uri.path)) ||
        uri.userInfo.isNotEmpty) {
      throw const AnimeException(AnimeError.changed);
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    _pending = id;
    try {
      final r = await _channel.invokeMapMethod<String, dynamic>('request', {
        'id': id,
        'origin': uri.origin,
        'path': '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
      });
      if (_pending != id) throw const AnimeException(AnimeError.cancelled);
      if (r == null ||
          r['status'] is! int ||
          r['body'] is! String ||
          (r['status'] as int) < 100 ||
          (r['status'] as int) > 599 ||
          (r['body'] as String).length > 3 * 1024 * 1024) {
        throw const AnimeException(AnimeError.changed);
      }
      return http.Response.bytes(
        base64Decode(r['body'] as String),
        r['status'] as int,
        headers: {
          if (r['type'] is String) 'content-type': r['type'] as String,
          if (r['blocked'] == true) 'cf-mitigated': 'challenge',
        },
      );
    } on FormatException {
      throw const AnimeException(AnimeError.changed);
    } on PlatformException catch (e) {
      throw AnimeException(switch (e.code) {
        'cancelled' => AnimeError.cancelled,
        'changed' => AnimeError.changed,
        _ => AnimeError.unreachable,
      });
    } on MissingPluginException {
      throw const AnimeException(AnimeError.unreachable);
    } finally {
      if (_pending == id) _pending = null;
    }
  }

  Future<void> cancel() async {
    final id = _pending;
    _pending = null;
    if (id != null) {
      try {
        await _channel.invokeMethod<void>('cancel', {'id': id});
      } on PlatformException {
        /* The Activity may already be destroyed. */
      } on MissingPluginException {
        /* No pending native request remains. */
      }
    }
  }
}
