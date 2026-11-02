import 'dart:async';

import 'package:flick/addons.dart';
import 'package:flick/downloads.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/kit/rail.dart';
import 'package:flick/main.dart';
import 'package:flick/screens/anime.dart';
import 'package:flick/screens/discover.dart';
import 'package:flick/screens/sources.dart';
import 'package:flick/screens/title.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Addon implements Addon {
  @override
  String get scopeId => id;
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
  List<Catalog> catalogs = const [];
  @override
  String get capability => 'Catalogs';
}

/// 40 titles per catalog, one page; a search finds 3. [respond] overrides a request.
class _Addons extends Addons {
  _Addons({bool empty = false}) {
    if (!empty) {
      _addon.catalogs = [
        (addon: _addon, type: 'movie', id: 'top', name: 'Popular', searchable: true, genres: const []),
        (addon: _addon, type: 'movie', id: 'year', name: 'New', searchable: false, genres: const []),
        (addon: _addon, type: 'series', id: 'top', name: 'Popular', searchable: true, genres: const []),
      ];
    }
  }
  final _addon = _Addon();
  final genres = <String?>[];
  Future<List<MetaPreview>>? Function(Catalog c, String? search, int skip) respond = (_, _, _) => null;

  @override
  List<Catalog> get catalogs => _addon.catalogs;

  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, String? genre, int skip = 0}) {
    genres.add(genre);
    return respond(c, search, skip) ??
      Future.value([
        if (skip == 0)
          for (var i = 0; i < (search == null ? 40 : 3); i++)
            (id: '${c.id}-$search-$i', type: c.type, name: '${c.id} $i', poster: null, scope: null, releaseInfo: '2019'),
      ]);
  }

  @override
  Future<Meta> meta(String type, String id) => Completer<Meta>().future;
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
    device.tv = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<void> pumpApp(WidgetTester tester, {_Addons? with_, bool settle = true}) async {
    SharedPreferences.setMockInitialValues({});
    addons = with_ ?? _Addons();
    downloads = _Downloads();
    await saved.load();
    device.tv = true;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const FlickApp());
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation', const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')), (_) {});
    await tester.pumpAndSettle();
  }

  /// The label of the focused FocusFrame (posters are labelled "name, year").
  String? focused() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FocusFrame>()?.semanticLabel;

  /// The focused control's text (switch and chips carry no semantic label).
  String? focusedText() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    String? text;
    void visit(Element e) {
      if (text != null) return;
      if (e.widget is Text) {
        text = (e.widget as Text).data;
      } else {
        e.visitChildren(visit);
      }
    }

    (context as Element).visitChildren(visit);
    return text;
  }

  bool textFocused() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  bool railFocused() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FlickRail>() != null;

  testWidgets('TV genre tabs support remote activation and preserve focus after filtering', (tester) async {
    final fake = _Addons();
    fake._addon.catalogs = [
      (addon: fake._addon, type: 'movie', id: 'top', name: 'Popular', searchable: true, genres: const ['Action']),
    ];
    await pumpApp(tester, with_: fake);
    final choice = find.widgetWithText(TvChoice, 'Action');
    final frame = find.descendant(of: choice, matching: find.byType(FocusFrame));
    tester.widget<FocusableActionDetector>(
      find.descendant(of: frame, matching: find.byType(FocusableActionDetector)),
    ).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.select);
    expect(fake.genres.last, 'Action');
    expect(focusedText(), 'Action');
    expect(tester.widget<TvChoice>(choice).selected, isTrue);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.select);
    expect(fake.genres.last, isNull);
    expect(focusedText(), 'All genres');
  });

  testWidgets('1: entering Discover with nothing remembered focuses Movies, never a text field', (tester) async {
    await pumpApp(tester);
    expect(focusedText(), 'Movies', reason: 'launch is the first entry');

    // Search open, the tab's memory cleared, then in from the rail.
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Search titles');
    await key(tester, LogicalKeyboardKey.select);
    expect(textFocused(), isTrue);
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pumpAndSettle();
    await systemBack(tester);
    expect(railFocused(), isTrue);

    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedText(), 'Movies');
    expect(textFocused(), isFalse);
  });

  testWidgets('2: results arriving never move focus off the switch', (tester) async {
    final page = Completer<List<MetaPreview>>();
    await pumpApp(tester, with_: _Addons()..respond = (_, _, _) => page.future, settle: false);
    await tester.pump();
    await tester.pump();
    expect(focusedText(), 'Movies');

    page.complete([for (var i = 0; i < 10; i++) (id: 'm$i', type: 'movie', name: 'M $i', poster: null, scope: null, releaseInfo: '2020')]);
    await tester.pumpAndSettle();
    expect(find.text('M 0'), findsOneWidget);
    expect(focusedText(), 'Movies');
  });

  testWidgets('3: Down reaches the chips, then the grid; Right and Down move along it', (tester) async {
    await pumpApp(tester);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedText(), 'Popular');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'top 0, 2019');
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'top 1, 2019');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'top 6, 2019');
  });

  testWidgets('4: Back from Title focuses the poster that opened it', (tester) async {
    await pumpApp(tester);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'top 6, 2019');

    await key(tester, LogicalKeyboardKey.select);
    expect(find.byType(TitleScreen), findsOneWidget);

    await systemBack(tester);
    expect(find.byType(TitleScreen), findsNothing);
    expect(focused(), 'top 6, 2019');
  });

  testWidgets('5: changing a chip or the switch keeps focus on it', (tester) async {
    await pumpApp(tester);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedText(), 'New');
    await key(tester, LogicalKeyboardKey.select);
    expect(find.text('year 0'), findsOneWidget, reason: 'the New catalog shows');
    expect(focusedText(), 'New');

    await key(tester, LogicalKeyboardKey.arrowUp);
    if (focusedText() != 'Series') await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedText(), 'Series');
    await key(tester, LogicalKeyboardKey.select);
    expect(find.text('top 0'), findsOneWidget);
    expect(focusedText(), 'Series');
  });

  testWidgets('6: holding Down keeps moving into rows that were not built', (tester) async {
    await pumpApp(tester);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'top 0, 2019');
    // cacheExtent is one viewport: rows 3 and later are not built from the top.
    expect(find.text('top 20'), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focused(), 'top 35, 2019', reason: 'row 8 (index 35), the last row');
  });

  testWidgets('6b: moving down reveals the whole cell, labels included, inside the safe area', (tester) async {
    await pumpApp(tester);
    for (var i = 0; i < 5; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focused(), 'top 15, 2019');
    final label = tester.getRect(find.text('top 15'));
    expect(label.bottom, lessThanOrEqualTo(540 - FlickTv.insetV));
  });

  testWidgets('7: Search focuses the field; Back closes it and returns to Search', (tester) async {
    await pumpApp(tester);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    expect(textFocused(), isTrue);

    await tester.enterText(find.byType(TextField), 'kid');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('top 2'), findsOneWidget, reason: 'the results show');
    expect(textFocused(), isTrue, reason: 'focus stays in the field');
    final path = <String?>[];
    for (var i = 0; i < 4 && !(focused()?.startsWith('top') ?? false); i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
      path.add(focused() ?? focusedText());
    }
    expect(focused(), matches(r'^top [0-2], 2019$'), reason: 'Down enters the results: $path');

    await systemBack(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('top 20'), findsNothing);
    expect(find.text('top 0'), findsOneWidget, reason: 'the catalog is back');
    expect(focused(), 'Search titles');
    expect(railFocused(), isFalse);
    expect(find.byKey(const ValueKey('rail-panel')), findsNothing);
  });

  testWidgets('multi-catalog TV search keeps focus as slower sources finish at larger text', (tester) async {
    final fake = _Addons();
    final second = fake._addon.catalogs[1];
    fake._addon.catalogs[1] = (addon: second.addon, type: second.type, id: second.id,
        name: second.name, searchable: true, genres: second.genres);
    final slow = Completer<List<MetaPreview>>();
    fake.respond = (c, q, _) => q != null && c.id == 'top' ? slow.future : null;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, with_: fake);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    await tester.enterText(find.byType(TextField), 'kid');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('year 0'), findsOneWidget);
    expect(textFocused(), isTrue);
    for (var i = 0; i < 4 && !(focused()?.startsWith('year') ?? false); i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focused(), matches(r'^year [0-2], 2019$'));
    final before = primaryFocus;
    slow.complete([(id: 'tt1', type: 'movie', name: 'Slow source result', poster: null, scope: null, releaseInfo: null)]);
    await tester.pumpAndSettle();
    expect(find.text('Slow source result'), findsOneWidget);
    expect(primaryFocus, before);
    expect(tester.takeException(), isNull);
    await systemBack(tester);
    expect(find.byType(TextField), findsNothing);
    expect(focused(), 'Search titles');
  });

  testWidgets('8: with no catalogs, Add sources is reachable and opens Sources', (tester) async {
    await pumpApp(tester, with_: _Addons(empty: true));
    expect(find.text('No catalogs for this type yet.'), findsOneWidget);
    expect(focusedText(), 'Movies', reason: 'the notice never steals valid focus');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedText(), 'Add sources');
    await key(tester, LogicalKeyboardKey.select);
    expect(find.byType(SourcesScreen), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(SourcesScreen)))!.isFirst, isTrue, reason: 'the rail tab');
  });

  testWidgets('9: rings at the content edges stay inside the viewport', (tester) async {
    await pumpApp(tester);
    final viewport = tester.getRect(find.descendant(of: find.byType(DiscoverScreen), matching: find.byType(Scrollable)).first);
    void inside(String what) {
      final box = FocusManager.instance.primaryFocus!.context!.findRenderObject()! as RenderBox;
      final ring = (box.localToGlobal(Offset.zero) & box.size).inflate(FlickTv.ringWidth + FlickTv.ringGap);
      expect(ring.left, greaterThanOrEqualTo(viewport.left), reason: what);
      expect(ring.right, lessThanOrEqualTo(viewport.right), reason: what);
      expect(ring.top, greaterThanOrEqualTo(viewport.top), reason: what);
      expect(ring.bottom, lessThanOrEqualTo(viewport.bottom), reason: what);
    }

    inside('Movies');
    tester.widget<FocusFrame>(find.ancestor(of: find.text('Search'), matching: find.byType(FocusFrame))).focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(focused(), 'Search titles');
    inside('Search');
    tester.widget<FocusFrame>(find.ancestor(of: find.text('Movies'), matching: find.byType(FocusFrame))).focusNode!.requestFocus();
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedText(), 'Popular');
    inside('first chip');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'top 0, 2019');
    inside('first column, row 1');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'top 5, 2019');
    inside('first column, row 2');
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(focused(), 'top 9, 2019');
    inside('last column, row 2');
  });

  final rings = find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is FocusRing);

  testWidgets('10: with search open exactly one ring shows, and the page below does not move', (tester) async {
    await pumpApp(tester);
    final movies = tester.getRect(find.text('Movies'));
    final poster = tester.getRect(find.byType(NetImage).first);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Search titles');
    expect(rings, findsOneWidget);

    await key(tester, LogicalKeyboardKey.select);
    expect(textFocused(), isTrue);
    expect(rings, findsOneWidget, reason: 'the field only, no stale ring on Close');
    await tester.pump(const Duration(seconds: 2));
    expect(rings, findsOneWidget);
    expect(tester.getRect(find.text('Movies')), movies, reason: 'the 48 dp header row keeps its height');
    expect(tester.getRect(find.byType(NetImage).first), poster);

    // The D-pad reaches Close: Right on an empty field, or with the caret at the end of the text.
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Close search');
    expect(rings, findsOneWidget, reason: 'Close shows its own ring');

    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(textFocused(), isTrue);
    await tester.enterText(find.byType(TextField), 'ab');
    tester.widget<TextField>(find.byType(TextField)).controller!.selection = const TextSelection.collapsed(offset: 1);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(textFocused(), isTrue, reason: 'Right inside the text moves the caret');
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Close search');
  });

  testWidgets('11: the grid starts at y 175 (±6), and captions clear the ring and lift', (tester) async {
    await pumpApp(tester);
    final poster = tester.getRect(find.byType(NetImage).first);
    expect(poster.top, closeTo(175, 6));

    final caption = tester.getRect(find.text('top 0'));
    expect(caption.top - poster.bottom, FlickTv.captionGap);
    final lift = poster.height * (FlickTv.lift - 1) / 2;
    expect(FlickTv.captionGap, greaterThanOrEqualTo(FlickTv.ringGap + FlickTv.ringWidth + lift));

    final chip = tester.getRect(find.ancestor(of: find.text('Popular'), matching: find.byType(FocusFrame)).first);
    expect(poster.top - chip.bottom, greaterThanOrEqualTo(FlickTv.ringGap + FlickTv.ringWidth + lift),
        reason: 'the first row\'s ring and lift clear the chips');
  });

  testWidgets('12: a loading poster is a surface1 card, not a hole', (tester) async {
    await pumpApp(tester);
    expect(
      find.ancestor(
        of: find.byType(NetImage).first,
        matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == FlickTokens.surface1),
      ),
      findsOneWidget,
    );
  });

  testWidgets('13: Movies / Series sit on a 40 dp surface1 track; the catalog chips are outlined', (tester) async {
    await pumpApp(tester);
    Finder track(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
              (w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == FlickTokens.surface1),
        );
    expect(track('Movies'), findsOneWidget);
    expect(tester.element(track('Series')), same(tester.element(track('Movies'))), reason: 'one track holds both segments');
    expect(tester.getSize(track('Movies')).height, 40);
    expect(track('Popular'), findsNothing);
    expect(
      find.ancestor(
        of: find.text('Movies'),
        matching: find.byWidgetPredicate(
            (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == FlickTokens.surface2),
      ),
      findsOneWidget,
      reason: 'the selected segment is filled',
    );
    expect(find.descendant(of: track('Movies'), matching: find.byType(SlashMarker)), findsOneWidget);
    Finder outlined(String label) => find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) =>
              w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null),
        );
    expect(outlined('Popular'), findsOneWidget, reason: 'the selected chip keeps its outline (mockup)');
    expect(outlined('New'), findsOneWidget);
    expect(outlined('Movies'), findsNothing, reason: 'segments sit on their track instead');
  });

  testWidgets('14: offline, the grid becomes a notice whose Retry the D-pad reaches and that reloads', (tester) async {
    final fake = _Addons()..respond = (_, _, _) => Future.error(AddonException(AddonError.unreachable));
    await pumpApp(tester, with_: fake);
    expect(find.text("You're offline. Check your connection and try again."), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);

    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedText(), 'Retry');

    fake.respond = (_, _, _) => null;
    await key(tester, LogicalKeyboardKey.select);
    expect(find.textContaining("You're offline"), findsNothing);
    expect(find.text('top 0'), findsOneWidget);
  });

  /// Discover's fake plus two Kitsu catalogs.
  _Addons withAnime() {
    final fake = _Addons();
    fake._addon.catalogs = [
      ...fake._addon.catalogs,
      (addon: fake._addon, type: 'anime', id: 'kitsu-anime-trending', name: 'Trending', searchable: false, genres: const []),
      (addon: fake._addon, type: 'anime', id: 'kitsu-anime-airing', name: 'Airing', searchable: false, genres: const []),
    ];
    return fake;
  }

  Future<void> openAnime(WidgetTester tester) async {
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.arrowDown);
    await key(tester, LogicalKeyboardKey.select);
  }

  testWidgets('15: Anime opens on its first Kitsu chip with no search; a chip switches the feed and keeps focus',
      (tester) async {
    await pumpApp(tester, with_: withAnime());
    await openAnime(tester);
    expect(focusedText(), 'Trending');
    expect(find.descendant(of: find.byType(AnimeTab), matching: find.byType(TextField)), findsNothing,
        reason: 'no Miruro search on TV');
    expect(find.text('kitsu-anime-trending 0'), findsOneWidget);

    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedText(), 'Airing');
    await key(tester, LogicalKeyboardKey.select);
    expect(find.text('kitsu-anime-airing 0'), findsOneWidget);
    expect(focusedText(), 'Airing');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), startsWith('kitsu-anime-airing '), reason: 'Down reaches the grid');
  });

  testWidgets('16: with no anime catalogs, Anime offers Add sources, which selects the Sources tab', (tester) async {
    await pumpApp(tester);
    await openAnime(tester);
    expect(find.text('No anime catalogs are switched on.'), findsOneWidget);
    expect(focusedText(), 'Add sources');
    await key(tester, LogicalKeyboardKey.select);
    expect(find.byType(SourcesScreen), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(SourcesScreen)))!.isFirst, isTrue, reason: 'the rail tab');
  });

  testWidgets('17: back up from the grid, a chip brings the whole Anime header in, title included', (tester) async {
    await pumpApp(tester, with_: withAnime());
    await openAnime(tester);
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    final title = find.text('Anime');
    expect(title.evaluate().isEmpty || tester.getTopLeft(title).dy < 0, isTrue, reason: 'scrolled away with the grid');
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(focusedText(), 'Trending');
    expect(tester.getTopLeft(find.text('Anime')).dy, greaterThanOrEqualTo(FlickTv.insetV));
  });

  testWidgets('18: Anime at 1.3x text restores its header and poster focus after Title', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, with_: withAnime());
    await openAnime(tester);
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    final poster = focused();
    expect(poster, startsWith('kitsu-anime-trending '));
    await key(tester, LogicalKeyboardKey.select);
    expect(find.byType(TitleScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await systemBack(tester);
    expect(focused(), poster);
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(focusedText(), 'Trending');
    expect(tester.getTopLeft(find.text('Anime')).dy, greaterThanOrEqualTo(FlickTv.insetV));
    expect(tester.takeException(), isNull);
  });

  testWidgets('19: Anime loading and offline keep chip focus; Retry reloads the feed', (tester) async {
    final page = Completer<List<MetaPreview>>();
    final fake = withAnime()..respond = (c, _, _) => c.type == 'anime' ? page.future : null;
    await pumpApp(tester, with_: fake, settle: false);
    await tester.pump();
    await tester.pump();
    await openAnime(tester);
    expect(focusedText(), 'Trending');
    expect(find.descendant(of: find.byType(AnimeTab), matching: find.byType(Skeleton)), findsWidgets);
    page.completeError(AddonException(AddonError.unreachable));
    await tester.pumpAndSettle();
    expect(focusedText(), 'Trending');
    expect(find.text("You're offline. Check your connection and try again."), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedText(), 'Retry');
    fake.respond = (_, _, _) => null;
    await key(tester, LogicalKeyboardKey.select);
    expect(find.text('kitsu-anime-trending 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('20: Down at the end of Anime stays on the last row', (tester) async {
    await pumpApp(tester, with_: withAnime());
    await openAnime(tester);
    for (var i = 0; i < 8; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focused(), 'kitsu-anime-trending 35, 2019');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'kitsu-anime-trending 35, 2019');
    expect(railFocused(), isFalse);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(railFocused(), isTrue, reason: 'Left still opens the rail');
  });

}
