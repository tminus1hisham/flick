import 'dart:async';

import 'package:flick/kit/focus.dart';
import 'package:flick/live.dart';
import 'package:flick/screens/live.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

LiveEvent event(String name, {int sport = 1, String league = 'Premier League'}) => (
  id: 41, sport: sport, name: name, league: league,
  start: DateTime(2026, 11, 1, 18), status: 100,
);

class _Client extends LiveClient {
  int stops = 0;
  @override
  Future<void> stop() async { stops++; }
  final requests = <int>[];
  final pending = <int, Completer<List<LiveEvent>>>{};
  @override
  Future<List<LiveEvent>> events(int sport) {
    requests.add(sport);
    return (pending[sport] = Completer<List<LiveEvent>>()).future;
  }
  @override
  Future<List<LiveChannel>> channels(LiveEvent event) async => [
    (id: 1, sport: event.sport, eventId: event.id, site: 2001, name: 'English', available: true),
    (id: 2, sport: event.sport, eventId: event.id, site: 2001, name: 'Backup', available: false),
  ];
  @override
  Future<LiveSource> resolve(LiveChannel channel) async => throw PlatformException(code: 'unavailable', message: 'This channel is unavailable.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() { device.tv = false; });

  test('native bridge preserves source identity and resolves each time', () async {
    const channel = MethodChannel('flick/live');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return {'url': 'https://media.example/${calls.length}.m3u8', 'headers': {'Referer': 'https://source.example/'}};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final client = LiveClient();
    const source = (id: 3, eventId: 41, sport: 6, site: 2001, name: 'English', available: true);
    final first = await client.resolve(source), second = await client.resolve(source);
    expect(first.url, isNot(second.url));
    expect(second.headers['Referer'], 'https://source.example/');
    expect(calls.last.arguments, {'sport': 6, 'eventId': 41, 'id': 3, 'site': 2001});
    await client.stop();
    expect(calls.last.method, 'stop');
  });

  Future<void> pump(WidgetTester tester, _Client client, {bool active = true, bool tv = false}) async {
    device.tv = tv;
    tester.view.physicalSize = tv ? const Size(1920, 1080) : const Size(360, 640);
    tester.view.devicePixelRatio = tv ? 2 : 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
      home: LiveTab(client: client, active: active)));
    await tester.pump();
  }

  testWidgets('inactive tab is lazy; first visit loads once', (tester) async {
    final client = _Client();
    await pump(tester, client, active: false);
    expect(client.requests, isEmpty);
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: LiveTab(client: client)));
    await tester.pump();
    expect(client.requests, [1]);
    client.pending[1]!.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No events for Football.'), findsOneWidget);
  });

  testWidgets('sport switches ignore late results and show channel failure inline', (tester) async {
    final client = _Client();
    await pump(tester, client);
    expect(find.byType(Skeleton), findsWidgets);
    await tester.tap(find.text('Basketball'));
    await tester.pump();
    client.pending[2]!.complete([event('Basketball game', sport: 2)]);
    await tester.pumpAndSettle();
    client.pending[1]!.complete([event('Late football')]);
    await tester.pumpAndSettle();
    expect(find.text('Late football'), findsNothing);
    await tester.tap(find.text('Basketball game'));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('This channel is unavailable.'), findsOneWidget);
    expect(client.stops, 1);
    expect(find.text('Watch live'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connection failure offers retry and empty state', (tester) async {
    final client = _Client();
    await pump(tester, client);
    client.pending[1]!.completeError(PlatformException(code: 'unreachable', message: 'Check your connection.'));
    await tester.pumpAndSettle();
    expect(find.text('Check your connection.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    client.pending[1]!.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No events for Football.'), findsOneWidget);
  });

  for (final tv in [false, true]) {
    testWidgets('search filters games and leagues and clears on ${tv ? 'TV' : 'phone'}', (tester) async {
      final client = _Client();
      await pump(tester, client, tv: tv);
      client.pending[1]!.complete([
        event('Arsenal vs Chelsea'),
        event('Barcelona vs Madrid', league: 'La Liga'),
      ]);
      await tester.pumpAndSettle();
      final search = find.byType(TextField);
      await tester.enterText(search, '  mAdRiD  ');
      await tester.pumpAndSettle();
      expect(find.text('Arsenal vs Chelsea'), findsNothing);
      expect(find.text('Barcelona vs Madrid'), findsOneWidget);
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.text('Barcelona vs Madrid'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Barcelona vs Madrid'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.enterText(search, 'PREMIER');
      await tester.pumpAndSettle();
      expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
      expect(find.text('Barcelona vs Madrid'), findsNothing);
      await tester.enterText(search, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No games match your search.'), findsOneWidget);
      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.text('Arsenal vs Chelsea'), findsOneWidget);
      expect(find.text('Barcelona vs Madrid'), findsOneWidget);
      await tester.enterText(search, 'Arsenal');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Barcelona vs Madrid'), findsOneWidget);
      expect(client.requests, [1]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone events fit at 1.3x text with long names', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final client = _Client();
    await pump(tester, client);
    client.pending[1]!.complete([event('A very long home team name against another very long away team name')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('A very long home team'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV remote selects event and Back returns focus to the event', (tester) async {
    final client = _Client();
    await pump(tester, client, tv: true);
    client.pending[1]!.complete([event('Match on TV')]);
    await tester.pumpAndSettle();
    final row = find.ancestor(of: find.text('Match on TV'), matching: find.byType(FocusFrame)).first;
    tester.widget<FocusableActionDetector>(find.descendant(of: row, matching: find.byType(FocusableActionDetector)).first).focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(row, findsOneWidget);
    expect(tester.widget<FocusableActionDetector>(find.descendant(of: row, matching: find.byType(FocusableActionDetector)).first).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
