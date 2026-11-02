import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'addons.dart';

const maxOfflineSubtitleBytes = 2 * 1024 * 1024;
final _captionFilename = RegExp(r'^caption-[a-f0-9]{32}\.srt$');

/// Subtitle hosts never receive video-provider headers, even when a video needs authentication.
Future<String> readExternalSubtitle(String url, {http.Client? client}) async {
  final uri = Uri.parse(url);
  if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) throw const FormatException('Invalid subtitle URL');
  final transport = client ?? http.Client();
  Future<String> read() async {
    final response = await transport.send(http.Request('GET', uri));
    if (response.statusCode ~/ 100 != 2) throw StateError('HTTP ${response.statusCode}');
    if ((response.contentLength ?? 0) > maxOfflineSubtitleBytes) throw const FormatException('Subtitle is too large');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > maxOfflineSubtitleBytes) throw const FormatException('Subtitle is too large');
      bytes.add(chunk);
    }
    final body = bytes.takeBytes();
    if (body.isEmpty) throw const FormatException('Empty subtitle file');
    try { return utf8.decode(body); }
    on FormatException { return latin1.decode(body); }
  }
  try { return await read().timeout(const Duration(seconds: 20)); }
  finally { if (client == null) transport.close(); }
}

class OfflineSubtitle {
  const OfflineSubtitle({required this.path, required this.label, required this.lang});
  final String path, label, lang;
  Subtitle get subtitle => (id: label, url: Uri.file(path).toString(), lang: lang);

  Future<String> read() async {
    final file = File(path);
    if (await file.length() > maxOfflineSubtitleBytes) throw const FormatException('Subtitle is too large');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxOfflineSubtitleBytes) throw const FormatException('Invalid subtitle file');
    return utf8.decode(bytes);
  }
}

/// Download-owned sidecars. The registry contains local filenames, never source URLs or headers.
class OfflineSubtitles {
  OfflineSubtitles({Future<Directory> Function()? directory}) : _directory = directory ?? _defaultDirectory;
  final Future<Directory> Function() _directory;
  late SharedPreferences _prefs;
  Future<void>? _loaded;
  Future<void> _pending = Future.value();
  Map<String, Map<String, Object?>> _records = {};

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/offline-subtitles');

  Future<void> _load() => _loaded ??= () async {
    _prefs = await SharedPreferences.getInstance();
    try {
      final stored = jsonDecode(_prefs.getString('downloadSubtitles') ?? '{}') as Map;
      for (final entry in stored.entries) {
        try {
          final row = Map<String, Object?>.from(entry.value as Map);
          final files = (row['files'] as List).cast<String>();
          final active = row['file'] as String?;
          if (entry.key is! String || files.isEmpty || !files.every(_captionFilename.hasMatch) ||
              active != null && !files.contains(active) || row['label'] is! String || row['lang'] is! String) { continue; }
          _records[entry.key as String] = {...row, 'files': files};
        } catch (_) { /* One damaged sidecar record must not discard other downloads. */ }
      }
    } catch (_) { /* A damaged registry must not prevent offline video playback. */ }
  }();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) async { await _load(); return operation(); });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @protected
  Future<bool> persist(String value) => _prefs.setString('downloadSubtitles', value);

  Future<void> _commit(Map<String, Map<String, Object?>> records) async {
    if (!await persist(jsonEncode(records))) throw StateError('Could not save subtitle metadata');
    _records = records;
  }

  Future<OfflineSubtitle?> get(String id) => _serial(() async {
    final row = _records[id];
    final filename = row?['file'] as String?;
    if (filename == null) return null;
    final dir = await _directory();
    return OfflineSubtitle(path: '${dir.path}/$filename', label: row!['label'] as String, lang: row['lang'] as String);
  });

  Future<OfflineSubtitle> save(String id, {required String text, required String label, required String lang,
      required bool Function() exists}) => _serial(() async {
    final bytes = utf8.encode(text);
    if (text.trim().isEmpty || bytes.length > maxOfflineSubtitleBytes) {
      throw const FormatException('Subtitle must contain text and be at most 2 MB');
    }
    if (!exists()) throw StateError('Download was deleted');
    final dir = await _directory();
    await dir.create(recursive: true);
    final random = Random.secure();
    final filename = 'caption-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.srt';
    final old = _records[id];
    final oldFiles = [for (final f in (old?['files'] as List<String>?) ?? <String>[])
      if (f == old?['file'] || await File('${dir.path}/$f').exists()) f];
    // Journal the new filename before writing, so interrupted saves are still cleaned up with the video.
    final intent = <String, Object?>{'file': old?['file'], 'label': old?['label'] ?? label,
      'lang': old?['lang'] ?? lang, 'files': [filename, ...oldFiles]};
    await _commit({..._records, id: intent});
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    if (!exists()) throw StateError('Download was deleted');
    await _commit({..._records, id: {...intent, 'file': filename, 'label': label, 'lang': lang}});
    for (final oldFile in oldFiles) {
      try { await File('${dir.path}/$oldFile').delete(); }
      catch (_) { /* Retained filenames let video deletion retry failed cleanup. */ }
    }
    return OfflineSubtitle(path: file.path, label: label, lang: lang);
  });

  Future<void> remove(String id) => _serial(() async {
    final row = _records[id];
    if (row == null) return;
    final dir = await _directory();
    for (final filename in row['files'] as List<String>) {
      final file = File('${dir.path}/$filename');
      if (await file.exists()) await file.delete();
    }
    await _commit({..._records}..remove(id));
  });
}
