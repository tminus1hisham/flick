import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Contract for the Discover build (design/spec.md). Bodies are filled on branch discover-engine.

/// One installed addon: its manifest plus where it lives. Bundled addons ship as manifest snapshots;
/// [locked] ones (Cinemeta) can't be switched off.
class Addon {
  Addon(this.manifest, {required this.base, this.bundled = false, this.locked = false, this.enabled = true});

  /// The manifest URL minus `/manifest.json`.
  final String base;
  final Map<String, Object?> manifest;
  final bool bundled, locked;
  bool enabled;

  String get id => manifest['id'] as String;
  String get name => manifest['name'] as String;
  String get description => (manifest['description'] as String?) ?? '';
}

/// A catalog Discover can show: no required extra, type movie or series.
typedef CatalogRef = ({Addon addon, String type, String id, String name});

typedef MetaPreview = ({String id, String type, String name, String? poster, String? releaseInfo});

typedef Video = ({String id, String title, int? season, int? episode, DateTime? released, String? thumbnail});

typedef Meta = ({
  String id,
  String type,
  String name,
  String? poster,
  String? background,
  String? description,
  String? releaseInfo,
  String? runtime,
  List<String> genres,
  List<Video> videos,
});

typedef Sub = ({String id, String url, String lang});

/// One stream from an addon. Exactly one of [infoHash], [url], [externalUrl] is set; ytId streams are dropped.
typedef AddonStream = ({
  String? name,
  String? title,
  String? infoHash,
  int? fileIdx,
  List<String> trackers, // "tracker:" sources, without the prefix
  String? url,
  Map<String, String> headers, // behaviorHints.proxyHeaders.request
  String? externalUrl,
  String? filename,
  int? videoSize,
  String? videoHash,
  List<Sub> subtitles,
});

/// What a stream row shows, parsed from the addon's free text. Missing values stay null, never 0.
typedef StreamLabel = ({String quality, String release, int? seeders, String? size, String? origin});

enum AddFailure { notAddon, unreachable, offline, duplicate }

class AddonException implements Exception {
  const AddonException(this.failure);
  final AddFailure failure;

  @override
  String toString() => 'AddonException(${failure.name})';
}

class Addons extends ChangeNotifier {
  Addons({http.Client? client});

  /// Restores bundled switches and user-added manifests from shared_preferences. Runs before runApp.
  Future<void> load() => throw UnimplementedError();

  /// Bundled first (fixed order), then user-added in the order they were added.
  List<Addon> get installed => throw UnimplementedError();

  /// Accepts `stremio://`, a base URL or a manifest URL. Throws [AddonException].
  Future<Addon> install(String input) => throw UnimplementedError();

  /// Bundled, unlocked addons only.
  void setEnabled(Addon a, bool on) => throw UnimplementedError();

  /// User-added addons only. Returns its index for [restore].
  int remove(Addon a) => throw UnimplementedError();

  void restore(Addon a, int index) => throw UnimplementedError();

  List<CatalogRef> catalogs(String type) => throw UnimplementedError();

  Future<List<MetaPreview>> catalog(CatalogRef c, {int skip = 0}) => throw UnimplementedError();

  Future<List<MetaPreview>> search(String type, String query) => throw UnimplementedError();

  Future<Meta> meta(String type, String id) => throw UnimplementedError();

  /// Enabled addons that serve `stream` for this (type, id).
  List<Addon> streamSources(String type, String videoId) => throw UnimplementedError();

  /// One addon's streams, in the addon's own order, with its own 15 s timeout.
  Future<List<AddonStream>> streams(Addon a, String type, String videoId) => throw UnimplementedError();

  /// Every enabled subtitles addon, merged. Extras: videoSize, filename, videoHash when known.
  Future<List<Sub>> subtitles(String type, String videoId, {int? size, String? filename, String? hash}) =>
      throw UnimplementedError();
}

/// `magnet:?xt=urn:btih:{hash}&dn={filename or name}` plus `&tr=` per tracker.
String magnetOf(AddonStream s) => throw UnimplementedError();

StreamLabel labelOf(AddonStream s) => throw UnimplementedError();
