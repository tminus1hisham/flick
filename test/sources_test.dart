import 'dart:async';

import 'package:flick/addons.dart';
import 'package:flick/screens/sources.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Addon implements Addon {
  @override
  String get scopeId => id;
  _Addon(this.id, this.name, {this.bundled = false, this.locked = false, this.capability = 'Streams · Movies & series'});
  @override
  final String id, name, capability;
  @override
  final bool bundled, locked;
  @override
  String get base => 'https://$id.example';
  @override
  bool serves(String resource, String type, String id) => false;
  @override
  List<Catalog> get catalogs => const [];
}

class _Addons extends Addons {
  _Addons(this.list);
  final List<Addon> list;
  final off = <String>{};
  final calls = <String>[];
  final removedAt = <Addon, int>{};
  Completer<Addon>? pendingAdd;

  @override
  List<Addon> get all => list;
  @override
  bool isEnabled(Addon a) => !off.contains(a.id);
  @override
  Future<void> setEnabled(Addon a, bool on) async {
    calls.add('setEnabled ${a.id} $on');
    on ? off.remove(a.id) : off.add(a.id);
    notifyListeners();
  }

  @override
  Future<Addon> add(String input) {
    calls.add('add $input');
    return switch (input) {
      'nope' => Future.error(AddonException(AddonError.invalid)),
      'twice' => Future.error(AddonException(AddonError.duplicate)),
      _ => (pendingAdd = Completer()).future,
    };
  }

  @override
  Future<void> remove(Addon a) async {
    removedAt[a] = list.indexOf(a);
    list.remove(a);
    notifyListeners();
  }

  @override
  Future<void> restore(Addon a) async {
    calls.add('restore ${a.id}');
    list.insert(removedAt.remove(a)!, a);
    notifyListeners();
  }
}

late _Addons _fake;

Future<void> _pump(WidgetTester tester, {double textScale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(360, 640);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: flickTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const SourcesScreen(),
  ));
}

Future<void> _submit(WidgetTester tester, String link) async {
  await tester.enterText(find.byType(TextField), link);
  await tester.pumpAndSettle(); // the field scrolls its caret into view first
  await tester.ensureVisible(find.byType(FilledButton));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FilledButton));
}

void main() {
  setUp(() {
    _fake = _Addons([
      _Addon('cinemeta', 'Cinemeta', bundled: true, locked: true, capability: 'Catalogs · Title details'),
      _Addon('pdm', 'Public Domain Movies', bundled: true, capability: 'Catalogs · Torrents'),
      _Addon('watchhub', 'WatchHub', bundled: true, capability: 'Where to watch'),
      _Addon('northstar', 'Northstar'),
      _Addon('atlas', 'Atlas'),
    ]);
    addons = _fake;
  });

  testWidgets('bundled rows have switches; Cinemeta is locked on', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(tester.getSemantics(find.text('WatchHub')), isSemantics(hasToggledState: true, isToggled: true));
    expect(tester.getSemantics(find.text('Public Domain Movies')), isSemantics(hasToggledState: true));
    final cinemeta = tester.getSemantics(find.text('Cinemeta'));
    expect(cinemeta, isNot(isSemantics(hasToggledState: true)));
    expect(cinemeta.label, contains('Built-in, always enabled'));
    expect(find.byTooltip('Remove Northstar'), findsOneWidget);
    expect(find.byTooltip('Remove WatchHub'), findsNothing);
    semantics.dispose();
  });

  testWidgets('toggling a bundled addon calls setEnabled', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    await tester.tap(find.text('WatchHub'));
    await tester.pumpAndSettle();
    expect(_fake.calls, ['setEnabled watchhub false']);
    expect(tester.getSemantics(find.text('WatchHub')), isSemantics(hasToggledState: true, isToggled: false));
    await tester.tap(find.text('Cinemeta'));
    expect(_fake.calls, hasLength(1));
    semantics.dispose();
  });

  testWidgets('adding shows progress, and an invalid link shows the inline error', (tester) async {
    await _pump(tester);
    await _submit(tester, 'https://ok.example/manifest.json');
    await tester.pump();
    expect(find.text('Checking link…'), findsOneWidget);
    _fake.pendingAdd!.complete(_Addon('ok', 'Ok'));
    await tester.pumpAndSettle();
    expect(find.text('Add source'), findsOneWidget);

    await _submit(tester, 'nope');
    await tester.pumpAndSettle();
    expect(find.text("That isn't a Stremio addon link"), findsOneWidget);
    expect(find.text('nope'), findsOneWidget, reason: 'the pasted link is kept for a retry');
  });

  testWidgets('adding a duplicate shows "Already added"', (tester) async {
    await _pump(tester);
    await _submit(tester, 'twice');
    await tester.pumpAndSettle();
    expect(find.text('Already added'), findsOneWidget);
  });

  testWidgets('removing shows an inline Undo row; Undo restores at the same position', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Remove Northstar'));
    await tester.pumpAndSettle();
    expect(find.text('Northstar removed'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Northstar removed')).dy, lessThan(tester.getTopLeft(find.text('Atlas')).dy));
    expect(find.byTooltip('Remove Northstar'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(_fake.calls, ['restore northstar']);
    expect(find.text('Northstar removed'), findsNothing);
    expect(_fake.list.map((a) => a.id), ['cinemeta', 'pdm', 'watchhub', 'northstar', 'atlas']);
    expect(tester.getTopLeft(find.text('Northstar')).dy, lessThan(tester.getTopLeft(find.text('Atlas')).dy));
  });

  testWidgets('four addons and the form fit 360×640; 1.3× text does not overflow', (tester) async {
    _fake.list.removeLast();
    await _pump(tester);
    expect(tester.getBottomLeft(find.text('Add source')).dy, lessThan(616));
    await _pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
