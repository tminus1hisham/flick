import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/screens/seek.dart';

void main() {
  Widget ripple(int side, int seconds, {bool reduced = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 360),
            disableAnimations: reduced,
          ),
          child: SeekRipple(side: side, seconds: seconds),
        ),
      );

  double opacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.descendant(
          of: find.byType(SeekRipple),
          matching: find.byType(FadeTransition),
        ),
      )
      .opacity
      .value;

  Iterable<Transform> scaled(WidgetTester tester) => tester
      .widgetList<Transform>(
        find.descendant(
          of: find.byType(SeekRipple),
          matching: find.byType(Transform),
        ),
      )
      .where((t) => t.transform.getMaxScaleOnAxis() != 1);

  testWidgets('shows the running total', (tester) async {
    await tester.pumpWidget(ripple(1, 10));
    await tester.pumpWidget(ripple(1, 20));
    await tester.pumpAndSettle();
    expect(find.text('20 s'), findsOneWidget);
    expect(opacity(tester), 1);
  });

  testWidgets('pulses on a new total, not with reduced motion', (tester) async {
    await tester.pumpWidget(ripple(1, 10));
    await tester.pumpAndSettle();
    await tester.pumpWidget(ripple(1, 20));
    await tester.pump(const Duration(milliseconds: 16));
    expect(scaled(tester), isNotEmpty);

    await tester.pumpWidget(ripple(1, 10, reduced: true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(ripple(1, 20, reduced: true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(scaled(tester), isEmpty);
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
