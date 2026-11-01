import 'package:flick/history.dart';
import 'package:flick/kit/focus.dart';
import 'package:flick/screens/discover.dart';
import 'package:flick/screens/history.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingHistory extends ViewingHistory {
  bool fail = true;
  @override
  Future<void> remove(String type, String videoId) async {
    await super.remove(type, videoId);
    if (fail) throw StateError('Storage unavailable');
  }
}

Future<void> seed(int count) async {
  for (var i = 0; i < count; i++) {
    await history.save(WatchProgress(type: 'series', videoId: 'tt123:1:$i',
      title: 'Title $i', subtitle: 'Episode $i', position: const Duration(seconds: 123),
      duration: const Duration(minutes: 20)));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await history.load();
  });
  tearDown(() {
    device.tv = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<void> pump(WidgetTester tester, {bool tv = false, bool discover = false}) async {
    device.tv = tv;
    tester.view.physicalSize = tv ? const Size(1920, 1080) : const Size(1080, 1920);
    tester.view.devicePixelRatio = tv ? 2 : 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
      home: discover ? const Scaffold(body: DiscoverScreen()) : HistoryScreen(history)));
    await tester.pumpAndSettle();
  }

  testWidgets('removes only the selected episode and persists the change', (tester) async {
    await seed(2);
    await pump(tester);
    expect(find.text('Title 1'), findsOneWidget);
    expect(find.text('0:02:03 / 0:20:00'), findsNWidgets(2));
    await tester.tap(find.text('Remove from history').first);
    await tester.pumpAndSettle();
    expect(find.text('Title 1'), findsNothing);
    expect(find.text('Title 0'), findsOneWidget);
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.entries.single.videoId, 'tt123:1:0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear all requires confirmation, can cancel and persists an empty list', (tester) async {
    await seed(1);
    await pump(tester);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(history.entries.length, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Clear history'), findsNothing);
    expect(history.entries.length, 1);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    expect(find.text('No unfinished videos'), findsOneWidget);
    expect(find.text('Clear all'), findsNothing);
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed change stays retryable even after its last row disappears', (tester) async {
    await seed(1);
    final store = _FailingHistory();
    await store.load();
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: HistoryScreen(store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from history'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No unfinished videos'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsNothing);
    final restored = ViewingHistory();
    await restored.load();
    expect(restored.entries, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final tv in [false, true]) {
    testWidgets('Discover opens history and Back returns (${tv ? 'TV' : 'phone'})', (tester) async {
      await saved.load();
      await pump(tester, tv: tv, discover: true);
      await tester.tap(tv ? find.bySemanticsLabel('Viewing history') : find.byTooltip('Viewing history'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('No unfinished videos'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsNothing);
      expect(find.byType(DiscoverScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV remote reveals long history and keeps focus after removal at larger text', (tester) async {
    await seed(12);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    await pump(tester, tv: true);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'History Back');
    for (var i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    final node = FocusManager.instance.primaryFocus!;
    expect(node.context!.findAncestorWidgetOfExactType<RevealArea>(), isNotNull);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(scroll.pixels, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(history.entries.length, 11);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'History Back');
    expect(tester.takeException(), isNull);
  });
}
