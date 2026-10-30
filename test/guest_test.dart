import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:flick/addons.dart';
import 'package:flick/jellyfin.dart';
import 'package:flick/main.dart';
import 'package:flick/screens/anime.dart';
import 'package:flick/screens/discover.dart';
import 'package:flick/screens/account.dart';
import 'package:flick/screens/library.dart';
import 'package:flick/screens/search.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/session.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MetaPreview _kid = (id: 'tt0012349', type: 'movie', name: 'The Kid', poster: null, releaseInfo: '1921');

class _Addons extends Addons {
  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, int skip = 0}) async => const [];

  @override
  Future<Meta> meta(String type, String id) async => (
        id: id,
        type: type,
        name: 'The Kid',
        poster: null,
        background: null,
        logo: null,
        description: null,
        releaseInfo: '1921',
        runtime: null,
        imdbRating: null,
        genres: const <String>[],
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
    FlutterSecureStorage.setMockInitialValues({});
    await saved.load();
    session.client = null;
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

  test('first launch is not onboarded; guest and sign-out both stay onboarded', () async {
    final s = Session();
    await s.load();
    expect(s.onboarded, isFalse);
    await s.continueAsGuest();
    final again = Session();
    await again.load();
    expect(again.onboarded, isTrue);

    again
      ..client = JellyfinClient(server: 'https://srv', deviceId: 'd', token: 't')
      ..online = true;
    await again.logout();
    expect(again.loggedIn, isFalse);
    expect(again.onboarded, isTrue);
    expect(again.online, isFalse, reason: 'a guest playing a download must not reach for the server');
  });

  test('autoplay next defaults on and persists', () async {
    final s = Session();
    await s.load();
    expect(s.autoplayNext, isTrue);
    s.autoplayNext = false;
    final again = Session();
    await again.load();
    expect(again.autoplayNext, isFalse);
  });

  test('installs signed in before guest mode count as onboarded', () async {
    SharedPreferences.setMockInitialValues({'server': 'https://srv', 'userId': 'u1'});
    FlutterSecureStorage.setMockInitialValues({'token': 't'});
    final s = Session();
    await s.load();
    expect(s.onboarded, isTrue);
  });

  test('Jellyfin favourite and like hit the 10.9 user-data routes', () async {
    final seen = <String>[];
    final c = JellyfinClient(
      server: 'https://srv',
      deviceId: 'd',
      token: 't',
      userId: 'u1',
      client: MockClient((r) async {
        seen.add('${r.method} ${r.url}');
        return http.Response(jsonEncode({}), 200);
      }),
    );
    await c.setFavorite('i1', true);
    await c.setFavorite('i1', false);
    await c.setLiked('i1', true);
    await c.setLiked('i1', false);
    expect(seen, [
      'POST https://srv/UserFavoriteItems/i1?userId=u1',
      'DELETE https://srv/UserFavoriteItems/i1?userId=u1',
      'POST https://srv/UserItems/i1/Rating?userId=u1&likes=true',
      'DELETE https://srv/UserItems/i1/Rating?userId=u1&likes=false',
    ].map((s) => s.replaceAll('?userId=u1&likes=false', '?userId=u1')).toList());
    expect(Item({'Id': 'i1', 'UserData': {'IsFavorite': true, 'Likes': true}}).isFavorite, isTrue);
    expect(Item({'Id': 'i1', 'UserData': {'Likes': false}}).liked, isFalse);
  });

  testWidgets('a guest tapping favourite gets the sign-in sheet, and Not now changes nothing', (tester) async {
    await _openTitle(tester);
    await tester.tap(_favourite());
    await tester.pumpAndSettle();
    expect(find.text(Gate.favourite.title), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text(Gate.favourite.title), findsNothing);
    expect(saved.favourites, isEmpty);
    expect(_favourite(), findsOneWidget);
  });

  testWidgets('signing in from the gate completes the favourite the guest tapped', (tester) async {
    await _openTitle(tester);
    await tester.tap(_favourite());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    // Login's poster wall loops forever, so pump frames instead of settling.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Close sign in'), findsOneWidget);
    expect(find.text('Continue as guest'), findsNothing, reason: 'the guest link is for first launch only');

    // Stands in for a successful sign-in; Login pops itself after one.
    session.client = JellyfinClient(server: 'https://srv', deviceId: 'd', token: 't');
    await tester.tap(find.byTooltip('Close sign in'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(saved.favourites, [_kid]);
    expect(find.bySemanticsLabel('Remove from favourites'), findsOneWidget);
    session.client = null;
  });

  testWidgets('signing in from the gate never removes a favourite kept from an earlier sign-in', (tester) async {
    // Saved survives sign-out, and a guest always sees "off": a toggle here would delete it.
    await saved.toggleFavourite(_kid);
    await _openTitle(tester);
    await tester.tap(_favourite());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    session.client = JellyfinClient(server: 'https://srv', deviceId: 'd', token: 't');
    await tester.tap(find.byTooltip('Close sign in'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(saved.favourites, [_kid]);
    session.client = null;
  });

  testWidgets('a member favourites and likes without a gate', (tester) async {
    session.client = JellyfinClient(server: 'https://srv', deviceId: 'd', token: 't');
    addTearDown(() => session.client = null);
    await _openTitle(tester);
    await tester.tap(_favourite());
    await tester.tap(find.bySemanticsLabel('Like title'));
    await tester.pumpAndSettle();
    expect(find.text(Gate.favourite.title), findsNothing);
    expect(saved.favourites, [_kid]);
    expect(saved.isLiked(_kid.id), isTrue);
    expect(tester.getSemantics(find.bySemanticsLabel('Unlike title')).flagsCollection.isToggled, Tristate.isTrue);
  });

  testWidgets('signing in keeps the guest on Discover with its state and the ordered tabs', (tester) async {
    addons = _Addons();
    final signedIn = ValueNotifier(false);
    addTearDown(signedIn.dispose);
    final server = JellyfinClient(
      server: 'https://srv',
      deviceId: 'd',
      token: 't',
      userId: 'u',
      client: MockClient((r) async => http.Response(jsonEncode({'Items': []}), 200)),
    );
    await tester.pumpWidget(MaterialApp(
      theme: flickTheme(),
      home: ValueListenableBuilder(
        valueListenable: signedIn,
        builder: (_, member, _) => Shell(guest: !member),
      ),
    ));
    final before = tester.state(find.byType(DiscoverScreen));
    final guestBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect([for (final d in guestBar.destinations) (d as NavigationDestination).label],
        ['Discover', 'Anime', 'Downloads']);

    session.client = server;
    addTearDown(() => session.client = null);
    signedIn.value = true;
    await tester.pump();
    final memberBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect([for (final d in memberBar.destinations) (d as NavigationDestination).label],
        ['Home', 'Discover', 'Browse', 'Anime', 'Downloads']);
    expect(memberBar.selectedIndex, 1, reason: 'Discover, not Home');
    expect(tester.state(find.byType(DiscoverScreen, skipOffstage: false)), same(before));
  });

  testWidgets('Anime and Downloads carry over both ways and Browse falls back on sign-out', (tester) async {
    addons = _Addons();
    final signedIn = ValueNotifier(false);
    addTearDown(signedIn.dispose);
    final server = JellyfinClient(
      server: 'https://srv',
      deviceId: 'd',
      token: 't',
      userId: 'u',
      client: MockClient((r) async => http.Response(jsonEncode({'Items': []}), 200)),
    );
    addTearDown(() => session.client = null);
    await tester.pumpWidget(MaterialApp(
      theme: flickTheme(),
      home: ValueListenableBuilder(
        valueListenable: signedIn,
        builder: (_, member, _) => Shell(guest: !member),
      ),
    ));
    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pump();
    final animeState = tester.state(find.byType(AnimeTab));

    session.client = server;
    signedIn.value = true;
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 3);
    expect(tester.state(find.byType(AnimeTab)), same(animeState));

    session.client = null;
    signedIn.value = false;
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
    expect(tester.state(find.byType(AnimeTab)), same(animeState));

    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pump();
    session.client = server;
    signedIn.value = true;
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 4);

    session.client = null;
    signedIn.value = false;
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);

    session.client = server;
    signedIn.value = true;
    await tester.pump();
    await tester.tap(find.byType(NavigationDestination).at(2));
    await tester.pump();
    session.client = null;
    signedIn.value = false;
    await tester.pump();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Browse header has a 48 dp Search button that pushes Search', (tester) async {
    session.client = JellyfinClient(
      server: 'https://srv',
      deviceId: 'd',
      token: 't',
      userId: 'u',
      client: MockClient((r) async => http.Response(jsonEncode({'Items': []}), 200)),
    );
    addTearDown(() => session.client = null);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: const BrowseScreen()));
    await tester.pumpAndSettle();
    final button = find.byTooltip('Search');
    expect(button, findsOneWidget);
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Find something to watch'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(BrowseScreen), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
  });
}
