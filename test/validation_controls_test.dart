import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/kit/focus.dart';
import 'package:flick/kit/progress.dart';
import 'package:flick/kit/sheet.dart';
import 'package:flick/screens/player_feedback.dart';
import 'package:flick/screens/speed.dart';
import 'package:flick/screens/volume.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/widgets.dart';

void main() {
  tearDown(() {
    device.tv = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  for (final tv in [false, true]) {
    testWidgets('house controls fit large text with reduced motion (TV: $tv)', (tester) async {
      device.tv = tv;
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 320);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      double? selected;
      await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: tv), shortcuts: tvShortcuts,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true, textScaler: const TextScaler.linear(1.3)),
          child: child!),
        home: Scaffold(body: Builder(builder: (context) => Column(children: [
          TextButton(onPressed: () async {
            selected = await showFlickSheet<double>(context, (_) => const SpeedPanel(rate: 1));
          }, child: const Text('Speed')),
          TextButton(onPressed: () => showFlickSheet<void>(context, (_) => VolumePanel(
            stream: const Stream<double>.empty(), readVolume: () => 60, onChanged: (_) {}, onMute: () {})),
            child: const Text('Open volume')),
        ]))),
      ));
      await tester.tap(find.text('Speed'));
      await tester.pumpAndSettle();
      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      expect(sheet.animationController!.duration, Duration.zero);
      final current = find.ancestor(of: find.text('1×'), matching: find.byType(Semantics));
      expect(current.evaluate().any((e) => (e.widget as Semantics).properties.selected == true), isTrue);
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.ensureVisible(find.text('4×'));
        await tester.tap(find.text('4×'));
      }
      await tester.pumpAndSettle();
      expect(selected, tv ? 1.25 : 4);
      expect(find.byType(SpeedPanel), findsNothing);
      await tester.tap(find.text('Open volume'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Slider)).height, greaterThanOrEqualTo(48));
      if (tv) {
        expect(find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is FocusRing), findsWidgets);
      }
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(VolumePanel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('download track shows proportional progress and unknown-size skeleton', (tester) async {
    Future<void> pump(double? value) => tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Center(child: SizedBox(width: 200, child: FlickProgress(value: value, color: FlickTokens.progress))))));
    await pump(0.25);
    await tester.pumpAndSettle();
    final fill = find.byWidgetPredicate((w) => w is ColoredBox && w.color == FlickTokens.progress);
    expect(tester.getSize(fill), const Size(50, 4));
    await pump(0.75);
    await tester.pumpAndSettle();
    expect(tester.getSize(fill), const Size(150, 4));
    await pump(null);
    await tester.pumpAndSettle();
    expect(find.byType(Skeleton), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('player feedback is announced and dismissible by remote', (tester) async {
    final semantics = tester.ensureSemantics();
    var dismissed = false;
    await tester.pumpWidget(MaterialApp(shortcuts: tvShortcuts, theme: flickTheme(),
      home: Scaffold(body: PlayerFeedback(message: 'Could not change playback speed. Try again.',
        onDismiss: () => dismissed = true))));
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(dismissed, isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('TV feedback focuses Dismiss and restores the underlying control', (tester) async {
    device.tv = true;
    var visible = false;
    late StateSetter update;
    final underlying = FocusNode();
    await tester.pumpWidget(MaterialApp(shortcuts: tvShortcuts, theme: flickTheme(tv: true),
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return Scaffold(body: Stack(fit: StackFit.expand, children: [
          TextButton(focusNode: underlying, autofocus: true, onPressed: () {}, child: const Text('Speed')),
          if (visible) Positioned.fill(child: PlayerFeedback(message: 'Try again.',
            onDismiss: () => setState(() => visible = false))),
        ]));
      })));
    await tester.pumpAndSettle();
    expect(underlying.hasFocus, isTrue);
    update(() => visible = true);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<FocusFrame>()?.semanticLabel,
      'Dismiss message');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(visible, isFalse);
    expect(underlying.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    underlying.dispose();
  });
}
