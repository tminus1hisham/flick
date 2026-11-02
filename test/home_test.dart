import 'dart:async';

import 'package:flick/addons.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/screens/home.dart';
import 'package:flick/screens/discover.dart' show BrowseScreen;
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const film = (id: 'tt123', type: 'movie', name: 'Featured film', poster: null, scope: null, releaseInfo: '2026');
const other = (id: 'tt456', type: 'movie', name: 'Another film', poster: null, scope: null, releaseInfo: '2026');

class HomeAddons extends Addons {
  final source = Addon({'id': 'cinemeta', 'name': 'Cinemeta', 'resources': ['meta'], 'types': ['movie', 'series']},
    'https://example.test', bundled: true);
  bool fail = false;
  final requests = <String>[];
  @override
  List<Catalog> get catalogs => [for (final type in ['movie', 'series'])
    (addon: source, type: type, id: 'top', name: 'Popular', searchable: true, genres: const [])];
  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, String? genre, int skip = 0}) async {
    requests.add(c.type);
    if (fail && c.type == 'series') throw StateError('offline');
    return [film, other, film];
  }
  @override
  Future<Meta> meta(String type, String id) async => (
    id: id, type: type, name: id, poster: null, background: null, logo: null, description: 'A featured story.',
    scope: null, releaseInfo: null, runtime: null, imdbRating: null, genres: const <String>[],
    trailers: [(source: 'P6AaSMfXHbA', youtube: true)], videos: const <Video>[],
  );
}

void main() {
  late HomeAddons fake;
  final originalAddons = addons;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await saved.load(); await history.load(); await settings.load();
    addons = fake = HomeAddons();
    device.tv = false;
  });
  tearDown(() { addons = originalAddons; device.tv = false; TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(AppLifecycleState.resumed); });

  Future<void> pump(WidgetTester tester, Widget child, {bool tv = false, bool reduce = false}) async {
    device.tv = tv;
    tester.view.physicalSize = tv ? const Size(1280, 720) : const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), navigatorObservers: [homeRouteObserver],
      home: MediaQuery(data: MediaQueryData(size: tv ? const Size(1280, 720) : const Size(360, 640),
        textScaler: const TextScaler.linear(1.3), disableAnimations: reduce), child: Scaffold(body: child is FeaturedMovies ? SingleChildScrollView(child: child) : child))));
    await tester.pumpAndSettle();
  }

  testWidgets('home fits small phone and opens the preserved browser', (tester) async {
    await pump(tester, const DiscoverScreen(), reduce: true);
    expect(find.text('TONIGHT’S PICK'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Browse / Search'));
    await tester.pumpAndSettle();
    expect(find.byType(BrowseScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('carousel timing, pause, reduced motion and hidden tab', (tester) async {
    Widget feature({bool active = true}) => FeaturedMovies(candidates: Future.value([film, other]), active: active,
      autoplay: false, onOpen: (_) {}, onRetry: () {});
    await pump(tester, feature());
    final before = tester.widget<Text>(find.byWidgetPredicate((w) => w is Text && (w.data == film.name || w.data == other.name))).data;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text(before!), findsNothing);
    await tester.ensureVisible(find.text('Pause rotation'));
    await tester.tap(find.text('Pause rotation')); await tester.pump();
    final paused = find.text('1 / 2').evaluate().isNotEmpty;
    await tester.pump(const Duration(seconds: 30));
    expect(find.text(paused ? '1 / 2' : '2 / 2'), findsOneWidget);
    await pump(tester, feature(active: false));
    await tester.pump(const Duration(seconds: 30));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one fake preview stops on hidden tab, route cover and background', (tester) async {
    var created = 0, disposed = 0;
    Widget home(bool active) => DiscoverScreen(active: active, previewBuilder: (_, event) => _FakePreview(
      onMount: () { created++; event('playing'); }, onDispose: () => disposed++));
    await pump(tester, home(true));
    expect(find.byType(_FakePreview), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -700)); await tester.pumpAndSettle();
    expect(find.byType(_FakePreview), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, 900)); await tester.pumpAndSettle();
    expect(find.byType(_FakePreview), findsOneWidget);
    final beforeRoute = disposed;
    final initial = created;
    await tester.tap(find.byTooltip('Browse / Search')); await tester.pumpAndSettle();
    expect(disposed, beforeRoute + 1);
    await tester.pageBack(); await tester.pumpAndSettle();
    expect(created, greaterThan(initial));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(find.byType(_FakePreview), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await pump(tester, home(false));
    expect(find.byType(_FakePreview), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TV home has focusable controls and no large text overflow', (tester) async {
    await pump(tester, const DiscoverScreen(), tv: true, reduce: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); await tester.pump();
    expect(primaryFocus, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('catalog rows share movie request and retry series independently', (tester) async {
    fake.fail = true;
    await pump(tester, const DiscoverScreen(), reduce: true);
    await tester.drag(find.byType(ListView).first, const Offset(0, -650)); await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -400)); await tester.pumpAndSettle();
    expect(fake.requests.where((type) => type == 'movie').length, 1);
    expect(find.text('Retry Popular Series'), findsOneWidget);
    fake.fail = false;
    await tester.ensureVisible(find.text('Retry Popular Series'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry Popular Series')); await tester.pumpAndSettle();
    expect(find.text('Retry Popular Series'), findsNothing);
    final series = find.byWidgetPredicate((w) => w is HomeRow && w.label == 'Popular Series');
    final all = find.descendant(of: series, matching: find.text('See all'));
    await tester.ensureVisible(all); await tester.pumpAndSettle();
    await tester.tap(all); await tester.pumpAndSettle();
    expect(tester.widget<BrowseScreen>(find.byType(BrowseScreen)).initialCatalog!.type, 'series');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late featured response after disposal is ignored', (tester) async {
    final pending = Completer<List<MetaPreview>>();
    await pump(tester, FeaturedMovies(candidates: pending.future, active: true, autoplay: false,
      onOpen: (_) {}, onRetry: () {}));
    await tester.pumpWidget(const SizedBox());
    pending.complete([film]); await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked preview falls back and reduced motion never starts a preview', (tester) async {
    late ValueChanged<String> event;
    Widget feature() => FeaturedMovies(candidates: Future.value([film, other]), active: true, autoplay: true,
      onOpen: (_) {}, onRetry: () {}, previewBuilder: (_, callback) {
        event = callback;
        return _FakePreview(onMount: () => callback('playing'), onDispose: () {});
      });
    await pump(tester, feature());
    expect(find.byType(_FakePreview), findsOneWidget);
    event('blocked'); await tester.pumpAndSettle();
    expect(find.byType(_FakePreview), findsNothing);
    expect(find.text('Watch Trailer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, feature(), reduce: true);
    expect(find.byType(_FakePreview), findsNothing);
    final before = find.text('1 / 2').evaluate().isNotEmpty;
    await tester.pump(const Duration(seconds: 30));
    expect(find.text(before ? '1 / 2' : '2 / 2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TV horizontal row reveals later titles', (tester) async {
    final items = [for (var i = 0; i < 15; i++)
      (id: 'tt${100 + i}', type: 'movie', name: 'Movie $i', poster: null, scope: null, releaseInfo: null)];
    await pump(tester, FocusTraversalGroup(policy: ReadingOrderTraversalPolicy(requestFocusCallback: tvReveal),
      child: HomeRow(label: 'Movies', items: items, onOpen: (_) {})), tv: true, reduce: true);
    final frame = find.byWidgetPredicate((w) => w is FocusFrame && w.semanticLabel == 'Movie 0');
    final detector = find.descendant(of: frame, matching: find.byType(FocusableActionDetector));
    tester.widget<FocusableActionDetector>(detector).focusNode!.requestFocus(); await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); await tester.pumpAndSettle();
    }
    expect(primaryFocus?.context?.findAncestorWidgetOfExactType<FocusFrame>()?.semanticLabel, 'Movie 12');
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FakePreview extends StatefulWidget {
  const _FakePreview({required this.onMount, required this.onDispose});
  final VoidCallback onMount, onDispose;
  @override
  State<_FakePreview> createState() => _FakePreviewState();
}
class _FakePreviewState extends State<_FakePreview> {
  @override
  void initState() { super.initState(); widget.onMount(); }
  @override
  void dispose() { widget.onDispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => const Text('Preview');
}
