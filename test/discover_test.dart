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
        (addon: this, type: 'movie', id: 'top', name: 'Popular', searchable: true),
        (addon: this, type: 'movie', id: 'year', name: 'New', searchable: false),
        (addon: this, type: 'series', id: 'top', name: 'Popular', searchable: true),
        (addon: this, type: 'anime', id: 'anime', name: 'Anime catalog', searchable: true),
      ];
  @override
  String get capability => 'Catalogs';
}

/// 30 titles per catalog page; [respond] overrides a request.
class _Addons extends Addons {
  final _addon = _Addon();
  final requests = <(String, String, String?, int)>[];
  Future<List<MetaPreview>>? Function(Catalog c, String? search, int skip) respond = (_, _, _) => null;

  @override
  List<Catalog> get catalogs => _addon.catalogs;

  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, int skip = 0}) {
    requests.add((c.type, c.id, search, skip));
    return respond(c, search, skip) ??
        Future.value([
          if (search == null && skip < 60)
            for (var i = skip; i < skip + 30; i++)
              (id: '${c.type}-${c.id}-$i', type: c.type, name: '${c.type} ${c.id} $i', poster: null, releaseInfo: '2019'),
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

  testWidgets('a skeleton grid stands in until the first page arrives', (tester) async {
    final page = Completer<List<MetaPreview>>();
    _fake.respond = (_, _, skip) => skip == 0 ? page.future : null;
    await _pump(tester);
    await tester.pump();

    expect(find.byType(GridSkeleton), findsOneWidget);
    expect(find.text('movie top 0'), findsNothing);

    page.complete([(id: 'tt1', type: 'movie', name: 'Severance', poster: null, releaseInfo: '2022–')]);
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
