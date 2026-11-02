import 'dart:ui' show Tristate;

import 'package:flick/addons.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/saved.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MetaPreview _kid = (id: 'tt0012349', type: 'movie', name: 'The Kid', poster: null, scope: null, releaseInfo: '1921');

class _Addons extends Addons {
  @override
  Future<Meta> meta(String type, String id) async => (
        id: id,
        type: type,
        name: 'The Kid',
        poster: null,
        background: null,
        logo: null,
        description: null,
        scope: null, releaseInfo: '1921',
        runtime: null,
        imdbRating: null,
        genres: const <String>[],
        trailers: const <Trailer>[],
        videos: const <Video>[],
      );
  @override
  List<Addon> streamSources(String type, String videoId) => const [];
}

Future<void> _openTitle(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addons = _Addons();
  await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: const TitleScreen(_kid)));
  await tester.pumpAndSettle();
}

Finder _favourite() => find.bySemanticsLabel('Add to favourites');

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await saved.load();
  });

  test('device favourites and likes survive a reload', () async {
    await saved.toggleFavourite(_kid);
    await saved.toggleLike(_kid.id);
    final again = Saved();
    await again.load();
    expect(again.favourites, [_kid]);
    expect(again.isLiked(_kid.id), isTrue);

    await again.toggleFavourite(_kid);
    await again.toggleLike(_kid.id);
    final third = Saved();
    await third.load();
    expect(third.favourites, isEmpty);
    expect(third.isLiked(_kid.id), isFalse);
  });

  test('My List is independent, scopes custom titles, and survives reload/removal', () async {
    final a = (id: 'custom', type: 'movie', name: 'A', poster: null, releaseInfo: null,
      scope: (provider: 'a', titleId: 'custom'));
    final b = (id: 'custom', type: 'movie', name: 'B', poster: null, releaseInfo: null,
      scope: (provider: 'b', titleId: 'custom'));
    await saved.toggleMyList(a);
    await saved.toggleFavourite(b);
    expect(saved.inMyList(b), isFalse);
    expect(saved.isFavourite(a.id, scope: a.scope), isFalse);
    expect(saved.isFavourite(b.id, scope: b.scope), isTrue);
    final again = Saved(); await again.load();
    expect(again.inMyList(a), isTrue);
    expect(again.isFavourite(b.id, scope: b.scope), isTrue);
    await again.toggleFavourite(a);
    await again.toggleFavourite(b);
    expect(again.isFavourite(a.id, scope: a.scope), isTrue);
    expect(again.isFavourite(b.id, scope: b.scope), isFalse);
    await again.toggleMyList(a);
    final third = Saved(); await third.load();
    expect(third.myList, isEmpty);
    expect(third.isFavourite(a.id, scope: a.scope), isTrue);
  });

  test('legacy custom favourites remain unscoped and canonical IDs stay shared', () async {
    SharedPreferences.setMockInitialValues({'favourites': '[{"id":"custom","type":"movie","name":"Legacy"}]'});
    final store = Saved(); await store.load();
    expect(store.favourites.single.scope, isNull);
    expect(store.isFavourite('custom', scope: (provider: 'a', titleId: 'custom')), isFalse);
    await store.toggleFavourite(_kid);
    expect(store.isFavourite(_kid.id, scope: (provider: 'a', titleId: _kid.id)), isTrue);
    expect(store.myList, isEmpty);
  });

  test('autoplay next defaults on and persists', () async {
    final s = Settings();
    await s.load();
    expect(s.autoplayNext, isTrue);
    s.autoplayNext = false;
    final again = Settings();
    await again.load();
    expect(again.autoplayNext, isFalse);
  });

  testWidgets('favourite and like toggle on a title with no account', (tester) async {
    await _openTitle(tester);
    await tester.tap(_favourite());
    await tester.tap(find.bySemanticsLabel('Like title'));
    await tester.pumpAndSettle();
    expect(saved.favourites, [_kid]);
    expect(saved.isLiked(_kid.id), isTrue);
    expect(tester.getSemantics(find.bySemanticsLabel('Unlike title')).flagsCollection.isToggled, Tristate.isTrue);

    await tester.tap(find.bySemanticsLabel('Remove from favourites'));
    await tester.tap(find.bySemanticsLabel('Unlike title'));
    await tester.pumpAndSettle();
    expect(saved.favourites, isEmpty);
    expect(saved.isLiked(_kid.id), isFalse);
  });
}
