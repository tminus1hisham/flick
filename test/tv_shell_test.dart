import 'package:flick/addons.dart';
import 'package:flick/downloads.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/kit/rail.dart';
import 'package:flick/main.dart';
import 'package:flick/screens/anime.dart';
import 'package:flick/screens/discover.dart';
import 'package:flick/screens/sources.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  List<Catalog> get catalogs => [(addon: this, type: 'movie', id: 'top', name: 'Popular', searchable: true)];
  @override
  String get capability => 'Catalogs';
}

class _Addons extends Addons {
  final _addon = _Addon();
  @override
  List<Catalog> get catalogs => _addon.catalogs;
  @override
  Future<List<MetaPreview>> catalog(Catalog c, {String? search, int skip = 0}) async =>
      [(id: 'tt1', type: 'movie', name: 'The Kid', poster: null, releaseInfo: '1921')];
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

  Future<void> pumpApp(WidgetTester tester, {bool tv = true}) async {
    SharedPreferences.setMockInitialValues({});
    addons = _Addons();
    downloads = _Downloads();
    await saved.load();
    device.tv = tv;
    if (tv) FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    tester.view.physicalSize = tv ? const Size(1920, 1080) : const Size(1080, 1920);
    tester.view.devicePixelRatio = tv ? 2 : 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const FlickApp());
    await tester.pumpAndSettle();
  }

  /// The visible tab's leftmost focusable that isn't a text field (arrows move a caret there).
  FocusNode leftmost(WidgetTester tester, Type screen) {
    final nodes = FocusScope.of(tester.element(find.byType(screen)))
        .traversalDescendants
        .where((n) => n is! FocusScopeNode && n.context!.findAncestorWidgetOfExactType<EditableText>() == null)
        .toList()
      ..sort((a, b) => a.rect.left != b.rect.left ? a.rect.left.compareTo(b.rect.left) : a.rect.top.compareTo(b.rect.top));
    return nodes.first;
  }

  /// The rail item with focus, by its label; null when focus is elsewhere.
  String? railFocus() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null || context.findAncestorWidgetOfExactType<FlickRail>() == null) return null;
    return context.findAncestorWidgetOfExactType<FocusFrame>()?.semanticLabel;
  }

  Finder railLabel(String label) => find.descendant(of: find.byType(FlickRail), matching: find.text(label));

  double labelOpacity(WidgetTester tester, String label) => tester
      .widget<FadeTransition>(find.ancestor(of: railLabel(label), matching: find.byType(FadeTransition)).first)
      .opacity
      .value;

  int shownTab(WidgetTester tester) => tester
      .widget<IndexedStack>(find.ancestor(of: find.byType(DiscoverScreen, skipOffstage: false), matching: find.byType(IndexedStack)))
      .index!;

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// Android system Back (the remote's Back reaches Flutter as popRoute).
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation', const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')), (_) {});
    await tester.pumpAndSettle();
  }

  testWidgets('a: TV shows the rail and no bottom bar', (tester) async {
    await pumpApp(tester);
    expect(find.byType(FlickRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    for (final icon in [Icons.explore_outlined, animeIcon, Icons.download_outlined, Icons.settings_outlined]) {
      expect(find.descendant(of: find.byType(FlickRail), matching: find.byIcon(icon)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('rail-panel')), findsNothing, reason: 'collapsed while content has focus');
    expect(tester.getTopLeft(find.byType(DiscoverScreen)).dx, FlickTv.railColumn + FlickTv.contentGap);
  });

  testWidgets('b: Left from the content edge lands on the selected destination and expands the rail', (tester) async {
    await pumpApp(tester);
    for (final (tab, screen) in [('Discover', DiscoverScreen), ('Anime', AnimeTab)]) {
      leftmost(tester, screen).requestFocus();
      await tester.pumpAndSettle();
      expect(railFocus(), isNull);
      expect(find.byKey(const ValueKey('rail-panel')), findsNothing);

      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(railFocus(), tab);
      expect(tester.getSize(find.byKey(const ValueKey('rail-panel'))).width, FlickTv.railExpanded);
      expect(tester.getTopLeft(find.byKey(const ValueKey('rail-panel'))).dx, 0);
      for (final label in ['Discover', 'Anime', 'Downloads', 'Sources']) {
        expect(labelOpacity(tester, label), 1, reason: label);
      }
      expect(tester.getTopLeft(find.byType(screen)).dx, FlickTv.railColumn + FlickTv.contentGap,
          reason: 'the content never shifts');

      if (tab == 'Discover') {
        // The rail last had focus on Anime (it remembers that); entering it again still lands on Discover.
        await key(tester, LogicalKeyboardKey.arrowDown);
        await key(tester, LogicalKeyboardKey.arrowRight);
        await key(tester, LogicalKeyboardKey.arrowLeft);
        expect(railFocus(), 'Discover');

        // Select Anime for the second pass: the nearest rail item to Anime's content is not Anime.
        await key(tester, LogicalKeyboardKey.arrowDown);
        await key(tester, LogicalKeyboardKey.select);
        expect(shownTab(tester), 1);
      }
    }
  });

  testWidgets('c: Right from the rail returns to the item that had focus', (tester) async {
    await pumpApp(tester);
    final item = leftmost(tester, DiscoverScreen);
    item.requestFocus();
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(railFocus(), 'Anime');

    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(item.hasPrimaryFocus, isTrue);
    expect(find.byKey(const ValueKey('rail-panel')), findsNothing, reason: 'collapsed again');
  });

  testWidgets('d: Down from Discover reaches Anime, and Select shows Anime', (tester) async {
    await pumpApp(tester);
    leftmost(tester, DiscoverScreen).requestFocus();
    await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(railFocus(), 'Discover');

    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(railFocus(), 'Anime');
    expect(shownTab(tester), 0, reason: 'focus alone does not switch');

    await key(tester, LogicalKeyboardKey.select);
    expect(shownTab(tester), 1);
    expect(FocusScope.of(tester.element(find.byType(AnimeTab))).hasFocus, isTrue, reason: 'focus moves into Anime');
  });

  testWidgets('e: Back in the content focuses the rail; Back on the rail exits', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApp(tester);
    leftmost(tester, DiscoverScreen).requestFocus();
    await tester.pumpAndSettle();

    await systemBack(tester);
    expect(railFocus(), 'Discover');
    expect(calls, isNot(contains('SystemNavigator.pop')));
    expect(find.byType(DiscoverScreen), findsOneWidget, reason: 'the shell stays');

    await systemBack(tester);
    expect(calls, contains('SystemNavigator.pop'));
  });

  testWidgets('f: Sources is a rail destination inside the shell, not a route', (tester) async {
    await pumpApp(tester);
    await systemBack(tester);
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(railFocus(), 'Sources');

    await key(tester, LogicalKeyboardKey.select);
    expect(shownTab(tester), 3);
    expect(find.byType(SourcesScreen), findsOneWidget);
    expect(ModalRoute.of(tester.element(find.byType(SourcesScreen)))!.isFirst, isTrue);
    expect(find.byType(FlickRail), findsOneWidget);
  });

  testWidgets('g: the phone keeps the bottom bar and has no rail', (tester) async {
    await pumpApp(tester, tv: false);
    expect(find.byType(FlickRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    for (final tab in ['Discover', 'Anime', 'Downloads']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)), findsOneWidget);
    }
    expect(find.byType(SourcesScreen), findsNothing);
  });

  testWidgets('i: entering the rail paints the ring on the selected item (Left, then Back)', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpApp(tester);
    bool ring(String label) => find
        .descendant(
          of: find.descendant(
              of: find.byType(FlickRail),
              matching: find.byWidgetPredicate((w) => w is FocusFrame && w.semanticLabel == label)),
          matching: find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is FocusRing),
        )
        .evaluate()
        .isNotEmpty;

    for (final enter in [() => key(tester, LogicalKeyboardKey.arrowLeft), () => systemBack(tester)]) {
      leftmost(tester, DiscoverScreen).requestFocus();
      await tester.pumpAndSettle();
      expect(ring('Discover'), isFalse);

      await enter();
      expect(railFocus(), 'Discover');
      expect(ring('Discover'), isTrue);
      expect(ring('Anime'), isFalse);
    }
  });

  testWidgets('j: while the rail slides open, the items are clipped to the panel; at rest the ring is whole', (tester) async {
    await pumpApp(tester);
    leftmost(tester, DiscoverScreen).requestFocus();
    await tester.pumpAndSettle();
    final item = find.descendant(
        of: find.byType(FlickRail), matching: find.byWidgetPredicate((w) => w is FocusFrame && w.semanticLabel == 'Discover'));
    final clip = find.descendant(of: find.byKey(const ValueKey('rail-items')), matching: find.byType(ClipRect)).first;
    Rect clipRect() {
      final box = tester.renderObject<RenderClipRect>(clip);
      return MatrixUtils.transformRect(box.getTransformTo(null), box.clipper!.getClip(box.size));
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(FlickTv.railIn ~/ 3);
    final panel = tester.getRect(find.byKey(const ValueKey('rail-panel')));
    expect(panel.right, lessThan(FlickTv.railExpanded), reason: 'mid-slide');
    expect(clipRect().right, moreOrLessEquals(panel.right, epsilon: 0.01));
    const ring = FlickTv.ringGap + FlickTv.ringWidth;
    expect(tester.getRect(item).right + ring, lessThanOrEqualTo(panel.right),
        reason: 'the item grows with the panel, so its ring is never cut open');

    await tester.pumpAndSettle();
    final rest = tester.getRect(item).inflate(ring);
    final clipped = clipRect();
    expect(clipped.left <= rest.left && clipped.top <= rest.top && clipped.right >= rest.right && clipped.bottom >= rest.bottom,
        isTrue, reason: 'ring $rest inside clip $clipped');
  });

  testWidgets('h: with reduced motion the rail expands in one frame', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester);
    leftmost(tester, DiscoverScreen).requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(railFocus(), 'Discover');
    expect(tester.getTopLeft(find.byKey(const ValueKey('rail-panel'))).dx, 0);
    expect(labelOpacity(tester, 'Anime'), 1);
    // The rail's own animation is already at its end (the segment's ink highlight may still fade out).
    final panel = find.ancestor(of: find.byKey(const ValueKey('rail-panel')), matching: find.byType(SlideTransition)).first;
    expect(tester.widget<SlideTransition>(panel).position.status, AnimationStatus.completed);
  });
}
