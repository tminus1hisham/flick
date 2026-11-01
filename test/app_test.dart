import 'package:flick/addons.dart';
import 'package:flick/downloads.dart';
import 'package:flick/main.dart';
import 'package:flick/state.dart';
import 'package:flick/kit/toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Addon implements Addon {
  @override
  String get id => 'cinemeta';
  @override
  String get name => 'Cinemeta';
  @override
  String get base => 'https://v3-cinemeta.strem.io';
  @override
  bool get bundled => true;
  @override
  bool get locked => true;
  @override
  bool serves(String resource, String type, String id) => true;
  @override
  List<Catalog> get catalogs => [(addon: this, type: 'movie', id: 'top', name: 'Popular', searchable: true, genres: const [])];
  @override
  String get capability => 'Catalogs';
}

const _film = (id: 'tt1', type: 'movie', name: 'The Kid', poster: null, releaseInfo: '1921');

class _Addons extends Addons {
  final _addon = _Addon();
  @override
  List<Catalog> get catalogs => _addon.catalogs;
  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, String? genre, int skip = 0}) async => [_film];
  @override
  Future<Meta> meta(String type, String id) async => (
        id: 'tt1', type: 'movie', name: 'The Kid', poster: null, background: null, logo: null,
        description: null, releaseInfo: '1921', runtime: null, imdbRating: null, genres: <String>[], videos: <Video>[],
      );
  @override
  List<Addon> streamSources(String type, String videoId) => const [];
}

class _Downloads extends Downloads {}

void main() {
  final originalAddons = addons;
  final originalDownloads = downloads;
  tearDown(() {
    addons = originalAddons;
    downloads = originalDownloads;
  });

  testWidgets('first launch opens Discover with no sign-in, and a title can be favourited at once', (tester) async {
    SharedPreferences.setMockInitialValues({});
    addons = _Addons();
    downloads = _Downloads();
    await saved.load();
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FlickApp());
    await tester.pumpAndSettle();

    for (final tab in ['Discover', 'Anime', 'Live', 'Downloads']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('The Kid'), findsOneWidget);
    expect(find.textContaining('Sign in'), findsNothing);
    expect(find.textContaining('Continue as guest'), findsNothing);

    await tester.tap(find.text('The Kid'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();

    expect(saved.isFavourite('tt1'), isTrue);
    expect(tester.widget<ToggleAction>(find.byType(ToggleAction).first).on, isTrue);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('Sign in'), findsNothing);
  });
}
