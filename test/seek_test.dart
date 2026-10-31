import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/screens/seek.dart';

void main() {
  Widget ripple(int side, int seconds, {bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 196),
            disableAnimations: reduced,
          ),
          child: SeekRipple(side: side, seconds: seconds),
        ),
      );

  // The ripple's own fade; the label's switcher fades inside it.
  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find
            .descendant(
              of: find.byType(SeekRipple),
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;

  Iterable<Transform> sliding(WidgetTester tester) => tester
      .widgetList<Transform>(
        find.descendant(
          of: find.byType(SeekRipple),
          matching: find.byType(Transform),
        ),
      )
      .where((t) => t.transform.getTranslation().y != 0);

  testWidgets('shows the running total', (tester) async {
    await tester.pumpWidget(ripple(1, 10));
    await tester.pumpWidget(ripple(1, 20));
    await tester.pumpAndSettle();
    expect(find.text('20 s'), findsOneWidget);
    expect(opacity(tester), 1);
  });

  testWidgets('a new total slides in, not with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(ripple(1, 10));
    await tester.pumpAndSettle();
    await tester.pumpWidget(ripple(1, 20));
    await tester.pump(const Duration(milliseconds: 16));
    expect(sliding(tester), isNotEmpty);

    await tester.pumpWidget(ripple(1, 10, reduced: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(ripple(1, 20, reduced: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(sliding(tester), isEmpty);
  });

  testWidgets('switching sides fades out before moving', (tester) async {
    await tester.pumpWidget(ripple(1, 20));
    await tester.pumpAndSettle();
    final right = tester.getCenter(find.text('20 s')).dx;
    await tester.pumpWidget(ripple(-1, 10));
    await tester.pump(const Duration(milliseconds: 40));
    // Still on the right, fading.
    expect(tester.getCenter(find.text('20 s')).dx, right);
    expect(opacity(tester), lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('10 s')).dx, lessThan(400));
    expect(opacity(tester), 1);
  });

  testWidgets('side 0 during a switch stays hidden', (tester) async {
    await tester.pumpWidget(ripple(1, 20));
    await tester.pumpAndSettle();
    await tester.pumpWidget(ripple(-1, 10));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(ripple(0, 10));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
  });

  testWidgets('a switch back mid-fade returns to the first side', (
    tester,
  ) async {
    await tester.pumpWidget(ripple(1, 20));
    await tester.pumpAndSettle();
    final right = tester.getCenter(find.text('20 s')).dx;
    await tester.pumpWidget(ripple(-1, 10));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(ripple(1, 30));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('30 s')).dx, right);
    expect(opacity(tester), 1);
  });

  testWidgets('the rim steps over time, also with reduced motion', (
    tester,
  ) async {
    // The rim painter's step: 0 → 1 as the newest segment lights.
    double step() => (tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(SeekRipple),
                matching: find.byType(CustomPaint),
              ),
            )
            .firstWhere((p) => p.painter != null)
            .painter! as dynamic)
        .step
        .value as double;

    for (final reduced in [false, true]) {
      await tester.pumpWidget(ripple(1, 10, reduced: reduced));
      await tester.pumpAndSettle();
      expect(step(), 1);
      await tester.pumpWidget(ripple(1, 20, reduced: reduced));
      await tester.pump(const Duration(milliseconds: 40));
      expect(step(), inExclusiveRange(0, 1), reason: '$reduced');
      await tester.pumpAndSettle();
      expect(step(), 1);
    }
  });

  testWidgets('fades out on side 0 keeping the last total', (tester) async {
    await tester.pumpWidget(ripple(-1, 30));
    await tester.pumpAndSettle();
    await tester.pumpWidget(ripple(0, 30));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('30 s'), findsOneWidget);
    expect(opacity(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
  });
}
