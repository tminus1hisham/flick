import 'package:flutter/foundation.dart';

// Stub of the contract in design/spec.md ("Dart API"). The real file comes from branch discover-data;
// at merge, take that file over this one.

typedef MetaPreview = ({String id, String type, String name, String? poster, String? releaseInfo});
typedef Video = ({String id, String title, int? season, int? episode, DateTime? released, String? thumbnail});
typedef Meta = ({
  String id,
  String type,
  String name,
  String? poster,
  String? background,
  String? logo,
  String? description,
  String? releaseInfo,
  String? runtime,
  String? imdbRating,
  List<String> genres,
  List<Video> videos,
});
typedef Catalog = ({Addon addon, String type, String id, String name, bool searchable});
typedef AddonStream = ({
  String? name,
  String? title,
  String? infoHash,
  int? fileIdx,
  String? url,
  String? externalUrl,
  List<String> trackers,
  String? filename,
});
typedef StreamInfo = ({String quality, int? seeders, String? size, String? origin, List<String> lines});
typedef Subtitle = ({String id, String url, String lang});

abstract class Addon {
  String get id;
  String get name;
  String get base;
  bool get bundled;
  bool get locked;
  bool serves(String resource, String type, String id);
  List<Catalog> get catalogs;
  String get capability;
}

enum AddonError { invalid, unreachable, duplicate, server }

class AddonException implements Exception {
  const AddonException(this.kind);
  final AddonError kind;
}

class Addons extends ChangeNotifier {
  Future<void> load() => throw UnimplementedError();
  List<Addon> get all => throw UnimplementedError();
  List<Addon> get active => throw UnimplementedError();
  bool isEnabled(Addon a) => throw UnimplementedError();
  Future<void> setEnabled(Addon a, bool on) => throw UnimplementedError();
  Future<Addon> add(String input) => throw UnimplementedError();
  Future<void> remove(Addon a) => throw UnimplementedError();
  Future<void> restore(Addon a) => throw UnimplementedError();
  List<Catalog> get catalogs => throw UnimplementedError();
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, int skip = 0}) => throw UnimplementedError();
  Future<Meta> meta(String type, String id) => throw UnimplementedError();
  List<Addon> streamSources(String type, String videoId) => throw UnimplementedError();
  Future<List<AddonStream>> streams(Addon a, String type, String videoId) => throw UnimplementedError();
  Future<List<Subtitle>> subtitles(String type, String videoId) => throw UnimplementedError();
}

StreamInfo describe(AddonStream s) => throw UnimplementedError();
String magnetFor(AddonStream s) => throw UnimplementedError();
Future<void> openExternal(String url) => throw UnimplementedError();
