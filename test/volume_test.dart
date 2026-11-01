import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/screens/volume.dart';
import 'package:flick/theme.dart';

void main() {
  late double volume, unmutedVolume;
  late StreamController<double> changes;

  setUp(() {
    volume = unmutedVolume = 60;
    changes = StreamController<double>.broadcast();
  });
  tearDown(() => changes.close());

  void setVolume(double value) {
    if (value == 0 && volume > 0) unmutedVolume = volume;
    volume = value;
    changes.add(value);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: flickTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => VolumePanel(
                  stream: changes.stream,
                  readVolume: () => volume,
                  onChanged: setVolume,
                  onMute: () {
                    setVolume(volume == 0 ? unmutedVolume : 0);
                  },
                ),
              ),
              child: const Text('Open volume'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open volume'));
    await tester.pumpAndSettle();
  }

  testWidgets('slider lowers and raises volume by touch', (tester) async {
    await pump(tester);
    final rect = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(rect.left + rect.width * .25, rect.center.dy));
    await tester.pumpAndSettle();
    expect(volume, lessThan(60));
    expect(find.text('${volume.round()}%'), findsOneWidget);
    await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
    await tester.pumpAndSettle();
    expect(volume, greaterThan(60));
    expect(find.text('${volume.round()}%'), findsOneWidget);
  });

  testWidgets('reopening reads muted state without a new volume event', (
    tester,
  ) async {
    await pump(tester);
    final rect = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(rect.left + rect.width * .25, rect.center.dy));
    await tester.pumpAndSettle();
    final restoreVolume = volume;
    await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
    await tester.pumpAndSettle();
    expect(volume, 0);
    expect(find.text('0%'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open volume'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    expect(find.text('Unmute'), findsOneWidget);
    await tester.tap(find.text('Unmute'));
    await tester.pumpAndSettle();
    expect(volume, restoreVolume);
    expect(find.text('${restoreVolume.round()}%'), findsOneWidget);
  });

  testWidgets('remote arrows adjust focused slider within 0 to 100', (
    tester,
  ) async {
    volume = 100;
    await pump(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(volume, 100);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(volume, 99);
    setVolume(0);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(volume, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(volume, 1);
  });
}
