import 'dart:async';

import 'package:flick/kit/focus.dart';
import 'package:flick/kit/sidebar.dart';
import 'package:flick/live.dart';
import 'package:flick/screens/live_queue.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

LiveEvent game(int id, String name, {int sport = 1, String league = 'League'}) =>
  (id: id, sport: sport, name: name, league: league, start: DateTime(2026, 11, 2), status: 100);
LiveChannel server(LiveEvent event, int id, {bool available = true}) =>
  (id: id, sport: event.sport, eventId: event.id, site: 20, name: 'Server $id', available: available);
final current = game(1, 'Current game');
final another = game(2, 'Arsenal Chelsea');
final third = game(3, 'Madrid Barcelona', league: 'La Liga');

class _Client extends LiveClient {
  final pending = <int, Completer<List<LiveEvent>>>{};
  bool delayed = false;
  int cancellations = 0;
  @override
  Future<List<LiveEvent>> events(int sport) => delayed
    ? (pending[sport] = Completer<List<LiveEvent>>()).future
    : Future.value([another, third]);
  @override
  Future<List<LiveChannel>> channels(LiveEvent event) async => [server(event, 1), server(event, 2, available: false)];
  @override
  Future<void> cancelPrepared() async { cancellations++; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() { for (final event in liveQueue.items) { liveQueue.remove(event); } });
  tearDown(() { device.tv = false; });

  Future<void> pumpPanel(WidgetTester tester, _Client client, {bool tv = false,
      Future<bool> Function(LiveEvent, LiveChannel)? onSwitch}) async {
    device.tv = tv;
    tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)), child: child!),
      home: Scaffold(body: LiveQueuePanel(client: client, event: current, channel: server(current, 1),
        onSwitch: onSwitch ?? (_, _) async => true))));
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  test('native prepare, commit and cancel preserve channel and prepared source identity', () async {
    const bridge = MethodChannel('flick/live');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, (call) async {
      calls.add(call);
      return call.method == 'prepare' ? {'url': 'http://127.0.0.1/prepared', 'headers': <String, String>{}} : null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(bridge, null));
    final client = LiveClient();
    final source = await client.prepare(server(another, 1));
    await client.commit(source);
    await client.cancelPrepared();
    expect(calls.map((call) => call.method), ['prepare', 'commit', 'cancelPrepared']);
    expect(calls.first.arguments, {'sport': 1, 'eventId': 2, 'id': 1, 'site': 20});
    expect(calls[1].arguments, {'url': 'http://127.0.0.1/prepared'});
  });

  for (final tv in [false, true]) {
    testWidgets('search and queue mutations fit ${tv ? 'TV' : 'phone'} at 1.3 text', (tester) async {
      final client = _Client();
      await pumpPanel(tester, client, tv: tv);
      await tester.pumpAndSettle();
      if (tv) expect(FocusManager.instance.primaryFocus!.debugLabel, 'Live queue Close');
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '  la LIGA  ');
      await tester.pumpAndSettle();
      expect(find.text(another.name), findsNothing);
      expect(find.text(third.name), findsOneWidget);
      await tap(tester, find.text('Add to queue'));
      expect(liveQueue.items, [third]);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Chelsea');
      await tester.pumpAndSettle();
      await tap(tester, find.text('Add to queue'));
      expect(liveQueue.items, [third, another]);
      await tap(tester, find.byTooltip('Move up ${another.name}'));
      expect(liveQueue.items, [another, third]);
      if (tv) expect(FocusManager.instance.primaryFocus!.debugLabel, 'Live queue Close');
      await tap(tester, find.byTooltip('Remove ${another.name}'));
      expect(liveQueue.items, [third]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sport changes discard late search results', (tester) async {
    final client = _Client()..delayed = true;
    await pumpPanel(tester, client);
    await tester.ensureVisible(find.text('Basketball'));
    await tester.tap(find.text('Basketball'));
    await tester.pump();
    client.pending[2]!.complete([game(4, 'Basketball match', sport: 2)]);
    await tester.pumpAndSettle();
    client.pending[1]!.complete([game(5, 'Late football')]);
    await tester.pumpAndSettle();
    expect(find.text('Basketball match'), findsOneWidget);
    expect(find.text('Late football'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Server identifies current channel, disables unavailable and failed switch retains queue', (tester) async {
    liveQueue.add(another);
    final client = _Client();
    final switched = <LiveChannel>[];
    await pumpPanel(tester, client, onSwitch: (event, channel) async { switched.add(channel); return false; });
    await tester.pumpAndSettle();
    await tap(tester, find.text('Server'));
    expect(find.byIcon(Icons.check), findsOneWidget);
    final disabled = tester.widget<TextButton>(find.ancestor(of: find.text('Server 2 · Unavailable'), matching: find.byType(TextButton)));
    expect(disabled.onPressed, isNull);
    await tap(tester, find.text('Queue'));
    await tap(tester, find.text('Next game'));
    await tap(tester, find.text('Server 1'));
    expect(switched.single, server(another, 1));
    expect(liveQueue.items, [another]);
    expect(find.text('Could not switch this source. Retry or choose another server.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final outside in [false, true]) {
    testWidgets('${outside ? 'outside tap' : 'Back'} closes sidebar and restores trigger focus', (tester) async {
      device.tv = true;
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final trigger = FocusNode(debugLabel: 'Queue trigger');
      addTearDown(trigger.dispose);
      final client = _Client();
      int underlyingKeys = 0;
      await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: Builder(builder: (context) => Scaffold(
        body: Focus(onKeyEvent: (_, _) { underlyingKeys++; return KeyEventResult.ignored; },
          child: TextButton(focusNode: trigger, autofocus: true, onPressed: () => showPlaybackSidebar<void>(context,
            (_) => LiveQueuePanel(client: client, event: current, channel: server(current, 1), onSwitch: (_, _) async => true)),
            child: const Text('Open queue')))))));
      await tester.pumpAndSettle();
      await tap(tester, find.text('Open queue'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(underlyingKeys, 0);
      if (outside) { await tester.tapAt(const Offset(100, 300)); } else { await tester.binding.handlePopRoute(); }
      await tester.pumpAndSettle();
      expect(find.byType(LiveQueuePanel), findsNothing);
      expect(trigger.hasFocus, isTrue);
      expect(client.cancellations, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final landscape in [false, true]) {
    testWidgets('mobile live sheet fits ${landscape ? 'landscape' : 'portrait'} and keyboard at 1.3x', (tester) async {
      tester.view.physicalSize = landscape ? const Size(800, 360) : const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey<NavigatorState>();
      final client = _Client();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, theme: flickTheme(),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(1.3)), child: child!), home: const Scaffold()));
      showPlaybackSidebar<void>(key.currentContext!, (_) => LiveQueuePanel(
        client: client, event: current, channel: server(current, 1), onSwitch: (_, _) async => true));
      await tester.pumpAndSettle();
      final sheet = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
      sheet.controller!.jumpTo(sheet.minChildSize);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      final resized = tester.widget<DraggableScrollableSheet>(find.byType(DraggableScrollableSheet));
      expect(resized.minChildSize, lessThan(resized.maxChildSize));
      await tester.scrollUntilVisible(find.byType(TextField), 24,
        scrollable: find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down));
      await tester.enterText(find.byType(TextField), 'Chelsea');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LiveQueuePanel), findsNothing);
      expect(client.cancellations, 1);
    });
  }

  testWidgets('closing a pending switch cancels preparation and ignores late success', (tester) async {
    liveQueue.add(another);
    final client = _Client();
    final pending = Completer<bool>();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, theme: flickTheme(), home: const Scaffold()));
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => Scaffold(body: LiveQueuePanel(
      client: client, event: current, channel: server(current, 1), onSwitch: (_, _) => pending.future))));
    await tester.pumpAndSettle();
    await tap(tester, find.text('Next game'));
    await tap(tester, find.text('Server 1'));
    await tap(tester, find.byTooltip('Close live queue'));
    expect(client.cancellations, 1);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(liveQueue.items, [another]);
    expect(tester.takeException(), isNull);
  });
}
