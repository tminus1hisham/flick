import 'dart:async';

import 'package:flick/kit/focus.dart';
import 'package:flick/screens/subtitle_adjustments.dart';
import 'package:flick/state.dart';
import 'package:flick/subtitles.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() { device.tv = false; });

  test('appearance persists atomically and invalid values fall back safely', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = Settings();
    await settings.load();
    expect(settings.subtitleAppearance, defaultSubtitleAppearance);
    await settings.saveSubtitleAppearance((size: 150, background: false));
    final restored = Settings();
    await restored.load();
    expect(restored.subtitleAppearance, (size: 150, background: false));
    expect(restored.audioLanguage, isNull);
    expect(restored.subtitleLanguage, isNull);
    await expectLater(restored.saveSubtitleAppearance((size: 999, background: true)), throwsArgumentError);
    expect(restored.subtitleAppearance, (size: 150, background: false));
    final prefs = await SharedPreferences.getInstance();
    for (final bad in ['broken', '{}', '[]', '{"size":-1,"background":true}',
      '{"size":101,"background":true}', '{"size":100,"background":"false"}']) {
      await prefs.setString('subtitleAppearance', bad);
      expect(restored.subtitleAppearance, defaultSubtitleAppearance);
    }
    await restored.saveSubtitleAppearance(defaultSubtitleAppearance);
    expect(restored.subtitleAppearance, defaultSubtitleAppearance);
    expect(prefs.getKeys(), {'subtitleAppearance'});
  });

  test('Flutter caption rendering uses the selected scale, background and outline', () {
    final normal = subtitleView(defaultSubtitleAppearance);
    final larger = subtitleView((size: 150, background: false));
    expect(larger.style.fontSize, normal.style.fontSize! * 1.5);
    expect(normal.style.backgroundColor, isNotNull);
    expect(larger.style.backgroundColor, isNull);
    expect(larger.style.shadows, hasLength(4));
    expect(larger.style.color, FlickTokens.textPrimary);
  });

  test('timing is isolated by subtitle, retained for Retry, and discarded for a new video', () async {
    final applied = <double>[];
    final timing = SubtitleTiming((seconds) async { applied.add(seconds); });
    await timing.select('file:https://sub.test/one');
    await timing.set(750);
    expect(applied.last, 0.75);
    await timing.select('track:1');
    expect(timing.milliseconds, 0);
    await timing.set(-500);
    expect(applied.last, -0.5);
    await timing.select(null);
    expect(applied.last, 0);
    await timing.set(1000);
    expect(timing.milliseconds, 0);
    await timing.select('file:https://sub.test/one');
    expect(timing.milliseconds, 750);
    expect(applied.last, 0.75);
    await timing.set(0);
    expect(timing.milliseconds, 0);
    await timing.select('track:1');
    expect(applied.last, -0.5);
    timing.clear();
    await timing.select('track:1');
    expect(applied.last, 0);
    final nextVideo = SubtitleTiming((_) async {});
    await nextVideo.select('file:https://sub.test/one');
    expect(nextVideo.milliseconds, 0);
  });

  test('timing bounds and failed native writes preserve the previous offset and allow Retry', () async {
    var fail = false;
    final timing = SubtitleTiming((_) async { if (fail) throw StateError('native failure'); });
    await timing.select('track:1');
    await timing.set(90000);
    expect(timing.milliseconds, 30000);
    fail = true;
    await expectLater(timing.set(-1000), throwsStateError);
    expect(timing.milliseconds, 30000);
    fail = false;
    await timing.set(-90000);
    expect(timing.milliseconds, -30000);
  });

  test('an in-flight adjustment cannot leak into a newly selected subtitle', () async {
    final gate = Completer<void>();
    final writes = <double>[];
    final timing = SubtitleTiming((seconds) async {
      writes.add(seconds);
      if (seconds == 1) await gate.future;
    });
    await timing.select('track:1');
    final pending = timing.set(1000);
    await Future<void>.delayed(Duration.zero);
    final next = timing.select('track:2');
    gate.complete();
    await Future.wait([pending, next]);
    expect(writes, [0, 1, 0]);
    expect(timing.key, 'track:2');
    expect(timing.milliseconds, 0);
    await timing.select('track:1');
    expect(timing.milliseconds, 0);
  });

  for (final tv in [false, true]) {
    testWidgets('timing, size and contrast controls work at 1.3x text (${tv ? 'TV' : 'phone'})', (tester) async {
      device.tv = tv;
      tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var appearance = defaultSubtitleAppearance, delay = 0;
      await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tv ? tvShortcuts : null,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(1.3), disableAnimations: true), child: child!),
        home: Scaffold(body: Align(alignment: Alignment.topRight, child: SizedBox(width: tv ? 380 : 180,
          child: StatefulBuilder(builder: (context, change) => ListView(children: [SubtitleAdjustments(
            appearance: appearance, delay: delay, timingEnabled: true,
            onDelay: (value) async { change(() => delay = value); },
            onAppearance: (value) async { change(() => appearance = value); },
          )])))))));
      await tester.pumpAndSettle();
      Future<void> activate(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        if (tv) {
          final detector = find.descendant(of: find.widgetWithText(FocusFrame, label),
            matching: find.byType(FocusableActionDetector));
          tester.widget<FocusableActionDetector>(detector).focusNode!.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
        } else {
          await tester.tap(find.text(label));
        }
        await tester.pumpAndSettle();
      }
      await activate('Timing & appearance');
      await activate('Later +0.25 s');
      expect(tester.getSize(find.widgetWithText(tv ? FocusFrame : TextButton, 'Later +0.25 s')).height,
        greaterThanOrEqualTo(48));
      expect(delay, 250);
      expect(find.text('Timing · +0.25 s · later'), findsOneWidget);
      await activate('Earlier −0.25 s');
      await activate('Earlier −0.25 s');
      expect(delay, -250);
      await activate('Reset timing');
      expect(delay, 0);
      await activate('Larger');
      expect(appearance.size, 125);
      await activate('Dark outline');
      expect(appearance.background, isFalse);
      await activate('Reset size');
      expect(appearance.size, 100);
      await activate('Dark background');
      expect(appearance.background, isTrue);
      expect(find.textContaining('ASS styling is flattened'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Off disables timing, appearance errors remain visible and Retry saves the choice', (tester) async {
    var calls = 0;
    var fail = true;
    await tester.pumpWidget(MaterialApp(theme: flickTheme(), home: Scaffold(body: ListView(children: [
      SubtitleAdjustments(appearance: defaultSubtitleAppearance, delay: 0, timingEnabled: false,
        onDelay: (_) async { throw StateError('Timing must be disabled'); },
        onAppearance: (value) async { calls++; if (fail) throw StateError('Storage unavailable'); }),
    ]))));
    await tester.tap(find.text('Timing & appearance'));
    await tester.pumpAndSettle();
    final later = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Later +0.25 s'));
    expect(later.onPressed, isNull);
    await tester.ensureVisible(find.text('Larger'));
    await tester.tap(find.text('Larger'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOneWidget);
    fail = false;
    await tester.ensureVisible(find.text('Retry adjustment'));
    await tester.tap(find.text('Retry adjustment'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Retry adjustment'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
