import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/kit/focus.dart';
import 'package:flick/kit/sheet.dart';
import 'package:flick/screens/speed.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueChanged<double?> selected) async {
    await tester.pumpWidget(
      MaterialApp(
        shortcuts: tvShortcuts,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => selected(
                await showFlickSheet<double>(context, (_) => const SpeedPanel(rate: 1),
                ),
              ),
              child: const Text('Speed'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Speed'));
    await tester.pumpAndSettle();
  }

  for (final rate in [0.25, 1.0, 4.0]) {
    testWidgets('selects ${speedLabel(rate)} from the full speed range', (
      tester,
    ) async {
      double? selected;
      await open(tester, (value) => selected = value);
      expect(find.byType(FocusFrame), findsNWidgets(16));
      await tester.ensureVisible(find.text(speedLabel(rate)));
      await tester.tap(find.text(speedLabel(rate)));
      await tester.pumpAndSettle();
      expect(selected, rate);
    });
  }

  testWidgets(
    'remote starts on current speed and selects the next quarter step',
    (tester) async {
      double? selected;
      await open(tester, (value) => selected = value);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selected, 1.25);
    },
  );

  testWidgets('dismissing the selector leaves the speed unchanged', (
    tester,
  ) async {
    double? selected = 1;
    await open(tester, (value) => selected = value);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selected, isNull);
  });
}
