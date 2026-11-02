import 'dart:async';

import 'package:flick/addons.dart';
import 'package:flick/screens/discover.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Addon implements Addon {
  @override
  String get scopeId => id;
  bool filterable = false;
  bool searchNew = false;
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
  List<Catalog> get catalogs => [
        (addon: this, type: 'movie', id: 'top', name: 'Popular', searchable: true, genres: filterable ? const ['Action', 'Sci-Fi'] : const []),
        (addon: this, type: 'movie', id: 'year', name: 'New', searchable: searchNew, genres: const []),
        (addon: this, type: 'series', id: 'top', name: 'Popular', searchable: true, genres: filterable ? const ['Action', 'Sci-Fi'] : const []),
        (addon: this, type: 'anime', id: 'anime', name: 'Anime catalog', searchable: true, genres: const []),
      ];
  @override
  String get capability => 'Catalogs';
}

/// 30 titles per catalog page; [respond] overrides a request.
class _Addons extends Addons {
  final _addon = _Addon();
  final genres = <String?>[];
  final requests = <(String, String, String?, int)>[];
  Future<List<MetaPreview>>? Function(Catalog c, String? search, int skip) respond = (_, _, _) => null;

  @override
  List<Catalog> get catalogs => _addon.catalogs;

  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, String? genre, int skip = 0}) {
    requests.add((c.type, c.id, search, skip));
    genres.add(genre);
    return respond(c, search, skip) ??
        Future.value([
          if (search == null && skip < 60)
            for (var i = skip; i < skip + 30; i++)
              (id: '${c.type}-${c.id}-$i', type: c.type, name: '${c.type} ${c.id} $i', poster: null, scope: null, releaseInfo: '2019'),
        ]);
  }
}

late _Addons _fake;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: const Scaffold(body: DiscoverScreen())));
}

void main() {
  setUp(() => addons = _fake = _Addons());

  MetaPreview title(String id, String name) =>
      (id: id, type: 'movie', name: name, poster: null, scope: null, releaseInfo: null);

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('search shows each source as it arrives, deduplicates and retries only failures', (tester) async {
    _fake._addon.searchNew = true;
    final slow = Completer<List<MetaPreview>>();
    var fail = false;
    _fake.respond = (c, q, skip) => q == null ? null : c.id == 'top'
        ? fail ? Future.error(StateError('Unavailable')) : slow.future
        : Future.value(skip == 0 ? [title('tt1', 'Found elsewhere')] : []);
    await _pump(tester);
    await tester.pumpAndSettle();
    await search(tester, 'film');
    expect(find.text('Found elsewhere'), findsOneWidget);
    expect(_fake.requests.where((r) => r.$3 == 'film').map((r) => r.$2), ['top', 'year']);

    slow.complete([title('tt1', 'Duplicate'), title('tt2', 'Another result')]);
    await tester.pumpAndSettle();
    expect(find.text('Duplicate'), findsNothing);
    expect(find.text('Another result'), findsOneWidget);

    fail = true;
    await tester.drag(find.byType(CustomScrollView).last, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Found elsewhere'), findsOneWidget);
    expect(_fake.requests.where((r) => r.$3 == 'film' && r.$4 > 0),
        containsAll([('movie', 'top', 'film', 2), ('movie', 'year', 'film', 1)]));
    final before = _fake.requests.length;
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(_fake.requests.skip(before), [('movie', 'top', 'film', 2)]);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('search ignores late responses after query, type and enabled catalogs change', (tester) async {
    _fake._addon.searchNew = true;
    final old = Completer<List<MetaPreview>>();
    _fake.respond = (c, q, _) => q == 'old' ? old.future : q == null ? null :
        Future.value([title('tt2', '${c.type} ${c.id} result')]);
    await _pump(tester);
    await tester.pumpAndSettle();
    await search(tester, 'old');
    await search(tester, 'new');
    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.text('series top result'), findsOneWidget);
    old.complete([title('tt1', 'Stale result')]);
    await tester.pumpAndSettle();
    expect(find.text('Stale result'), findsNothing);
    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    expect(find.text('movie year result'), findsNothing); // Same canonical ID is deduplicated.
    _fake._addon.searchNew = false;
    _fake.notifyListeners();
    await tester.pumpAndSettle();
    final feed = tester.widget<CatalogFeed>(find.byType(CatalogFeed).last);
    expect(feed.searchCatalogs!.map((c) => c.id), ['top']);
    expect(find.text('Stale result'), findsNothing);
  });

  testWidgets('search bounds requests to four and stops queued work when disposed', (tester) async {
    final pending = List.generate(6, (_) => Completer<List<MetaPreview>>());
    var active = 0, peak = 0;
    _fake.respond = (c, _, _) async {
      active++;
      if (active > peak) peak = active;
      final page = await pending[int.parse(c.id)].future;
      active--;
      return page;
    };
    final catalogs = [for (var i = 0; i < 6; i++)
      (addon: _fake._addon, type: 'movie', id: '$i', name: 'Source $i', searchable: true, genres: <String>[])];
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: Scaffold(
      body: CatalogFeed.search(catalogs, query: 'film'))));
    await tester.pump();
    expect(_fake.requests.length, 4);
    pending[1].complete([title('tt1', 'First available')]);
    await tester.pumpAndSettle();
    expect(find.text('First available'), findsOneWidget);
    expect(_fake.requests.length, 5);
    expect(peak, 4);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < pending.length; i++) {
      if (!pending[i].isCompleted) pending[i].complete([]);
    }
    await tester.pumpAndSettle();
    expect(_fake.requests.length, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed searches offer retry instead of an empty-results message', (tester) async {
    _fake._addon.searchNew = true;
    var fail = true;
    _fake.respond = (_, q, _) => q == null ? null : fail
        ? Future.error(AddonException(AddonError.unreachable))
        : Future.value([]);
    await _pump(tester);
    await tester.pumpAndSettle();
    await search(tester, 'film');
    expect(find.text('Nothing found for “film”'), findsNothing);
    expect(find.text("Couldn't connect. Check your connection and try again."), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing found for “film”'), findsOneWidget);
  });

  testWidgets('genre tabs reset paging, survive empty results, and ignore stale pages', (tester) async {
    _fake._addon.filterable = true;
    final stale = Completer<List<MetaPreview>>();
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Action'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(_fake.requests.last.$4, greaterThan(0));
    expect(_fake.genres.last, 'Action');
    await tester.tap(find.text('All genres'));
    await tester.pumpAndSettle();
    _fake.respond = (_, _, _) => _fake.genres.last == 'Action' ? stale.future : Future.value([]);
    await tester.tap(find.text('Action'));
    await tester.pump();
    expect(_fake.genres.last, 'Action');
    expect(_fake.requests.last.$4, 0);
    await tester.tap(find.text('Sci-Fi'));
    await tester.pumpAndSettle();
    expect(_fake.genres.last, 'Sci-Fi');
    expect(find.text('No titles in this catalog yet.'), findsOneWidget);
    stale.complete([(id: 'stale', type: 'movie', name: 'Stale action', poster: null, scope: null, releaseInfo: null)]);
    await tester.pumpAndSettle();
    expect(find.text('Stale action'), findsNothing);
    _fake.respond = (_, _, _) => null;
    await tester.tap(find.text('All genres'));
    await tester.pumpAndSettle();
    expect(_fake.genres.last, isNull);
    expect(find.text('movie top 0'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(_fake.requests.last.$4, greaterThan(0));
    expect(_fake.genres.last, isNull);
  });

  testWidgets('a skeleton grid stands in until the first page arrives', (tester) async {
    final page = Completer<List<MetaPreview>>();
    _fake.respond = (_, _, skip) => skip == 0 ? page.future : null;
    await _pump(tester);
    await tester.pump();

    expect(find.byType(GridSkeleton), findsOneWidget);
    expect(find.text('movie top 0'), findsNothing);

    page.complete([(id: 'tt1', type: 'movie', name: 'Severance', poster: null, scope: null, releaseInfo: '2022–')]);
    await tester.pumpAndSettle();

    expect(find.byType(GridSkeleton), findsNothing);
    expect(find.text('Severance'), findsOneWidget);
    expect(tester.getSize(find.byType(AspectRatio).first).width, closeTo(98.7, 0.1));
  });

  testWidgets('an empty search offers Clear search, which restores the catalog where it was', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('movie top 9'));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(_fake.requests.last, ('movie', 'top', 'zzz', 0));
    expect(find.text('Nothing found for “zzz”'), findsOneWidget);
    expect(find.text('movie top 9'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing found for “zzz”'), findsNothing);
    expect(tester.getTopLeft(find.text('movie top 9')), before);
  });

  testWidgets('a failed next page keeps the grid and offers Retry', (tester) async {
    var fail = true;
    _fake.respond = (_, _, skip) => skip == 30 && fail ? Future.error(StateError('boom')) : null;
    await _pump(tester);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -5000));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load more titles"), findsOneWidget);
    expect(find.text('movie top 29'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing);
    expect(_fake.requests.last, ('movie', 'top', null, 30));
  });

  testWidgets('Movies / Series switches the catalog and chips', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
    expect(find.text('movie top 0'), findsOneWidget);

    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();

    expect(_fake.requests.last, ('series', 'top', null, 0));
    expect(find.text('series top 0'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(tester.getSemantics(find.text('Series')), isSemantics(label: 'Series', isSelected: true));

    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();

    expect(_fake.requests.last, ('movie', 'year', null, 0));
    expect(find.text('movie year 0'), findsOneWidget);
  });

  testWidgets('Discover has no Anime segment or anime catalog chips', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('Anime'), findsNothing);
    expect(find.text('Anime catalog'), findsNothing);
    expect(find.byType(CatalogFeed), findsOneWidget);

    await tester.tap(find.text('Series'));
    await tester.pumpAndSettle();
    expect(find.text('Anime catalog'), findsNothing);
    expect(_fake.requests.every((r) => r.$1 != 'anime'), isTrue);
  });
}
