import 'package:flick/kit/focus.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void highlight(FocusHighlightStrategy strategy) {
    FocusManager.instance.highlightStrategy = strategy;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
  }

  Future<void> pump(WidgetTester tester, Widget frame, {Map<ShortcutActivator, Intent>? shortcuts, bool reduceMotion = false}) =>
      tester.pumpWidget(MaterialApp(
        theme: flickTheme(tv: true),
        shortcuts: shortcuts,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Center(child: SizedBox(width: 140, height: 210, child: frame)),
        ),
      ));

  final ring = find.byWidgetPredicate((w) => w is CustomPaint && w.foregroundPainter is FocusRing);

  testWidgets('the ring shows while focused in traditional highlight mode, not in touch mode', (tester) async {
    highlight(FocusHighlightStrategy.alwaysTraditional);
    final node = FocusNode();
    addTearDown(node.dispose);
    await pump(tester, FocusFrame(focusNode: node, child: const SizedBox.expand()));
    expect(ring, findsNothing, reason: 'not focused yet');

    node.requestFocus();
    await tester.pump();
    expect(ring, findsOneWidget);

    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    await tester.pump();
    expect(node.hasFocus, isTrue);
    expect(ring, findsNothing);
  });

  testWidgets('a frame handed another node shows that node\'s state, not the old ring', (tester) async {
    highlight(FocusHighlightStrategy.alwaysTraditional);
    final a = FocusNode(debugLabel: 'a'), b = FocusNode(debugLabel: 'b'), c = FocusNode(debugLabel: 'c');
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    addTearDown(c.dispose);
    // The same element is reused for each pump: only the node changes.
    Future<void> frame(FocusNode node, {bool other = false}) => pump(
        tester,
        Column(children: [
          Expanded(child: FocusFrame(focusNode: node, child: const SizedBox.expand())),
          if (other) Focus(focusNode: c, child: const SizedBox(height: 10)),
        ]));

    await frame(a);
    a.requestFocus();
    await tester.pump();
    expect(ring, findsOneWidget);

    await frame(b);
    await tester.pump();
    expect(b.hasFocus, isFalse);
    expect(ring, findsNothing, reason: 'b is not focused');
    await tester.pump(const Duration(seconds: 2));
    expect(ring, findsNothing, reason: 'still no stale ring');

    b.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(ring, findsOneWidget, reason: 'b focused');
    b.unfocus();
    await tester.pump();
    await tester.pump();
    expect(ring, findsNothing, reason: 'b unfocused');

    // Handed a node that already has focus: the ring shows at once.
    await frame(b, other: true);
    c.requestFocus();
    await tester.pump();
    expect(ring, findsNothing);
    await frame(c);
    await tester.pump();
    expect(c.hasFocus, isTrue);
    expect(ring, findsOneWidget, reason: 'c is focused');
  });

  testWidgets('Select and Enter activate once per press', (tester) async {
    var activations = 0;
    await pump(tester, FocusFrame(autofocus: true, onActivate: () => activations++, child: const SizedBox.expand()),
        shortcuts: tvShortcuts);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(activations, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activations, 2);
  });

  testWidgets('a held Select activates once under tvShortcuts', (tester) async {
    var activations = 0;
    await pump(tester, FocusFrame(autofocus: true, onActivate: () => activations++, child: const SizedBox.expand()),
        shortcuts: tvShortcuts);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(activations, 1);
  });

  testWidgets('a focused lift frame scales by 1.03, and not at all with reduced motion', (tester) async {
    highlight(FocusHighlightStrategy.alwaysTraditional);
    double scale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

    await pump(tester, const FocusFrame(autofocus: true, lift: true, child: SizedBox.expand()));
    await tester.pump();
    expect(scale(), FlickTv.lift);

    await pump(tester, const FocusFrame(autofocus: true, lift: true, child: SizedBox.expand()), reduceMotion: true);
    await tester.pump();
    expect(scale(), 1);
    expect(ring, findsOneWidget, reason: 'reduced motion keeps the ring');
  });

  testWidgets('FocusFrame.button has exactly one focusable node', (tester) async {
    // Focus nodes inside the frame (the Navigator owns one too).
    int focusable() => FocusManager.instance.rootScope.descendants
        .where((n) => n.canRequestFocus && n.context?.findAncestorWidgetOfExactType<FocusFrame>() != null)
        .length;

    var taps = 0;
    await pump(tester, FocusFrame.button(onActivate: () => taps++, child: const SizedBox.expand()));
    expect(focusable(), 1);
    await tester.tap(find.byType(InkWell));
    expect(taps, 1, reason: 'touch still works through the InkWell');

    // The count sees a stray focus owner: an InkWell that may take focus adds a second node.
    await pump(tester, FocusFrame(child: Material(child: InkWell(onTap: () {}, child: const SizedBox.expand()))));
    expect(focusable(), 2);
  });

  testWidgets('the ring paints ringWidth + ringGap outside the child on every side', (tester) async {
    highlight(FocusHighlightStrategy.alwaysTraditional);
    await pump(tester, const FocusFrame(autofocus: true, child: SizedBox.expand()));
    await tester.pump();

    const r = FlickTokens.artworkRadius, gap = FlickTv.ringGap, w = FlickTv.ringWidth;
    const child = Rect.fromLTWH(0, 0, 140, 210);
    expect(
      ring,
      paints
        ..drrect(
          outer: RRect.fromRectAndRadius(child.inflate(gap + w), const Radius.circular(r + gap + w)),
          inner: RRect.fromRectAndRadius(child.inflate(gap), const Radius.circular(r + gap)),
          color: FlickTokens.textPrimary,
        ),
    );
  });

  test('the phone theme keeps its focus colours; TV makes focus overlays transparent', () {
    const focused = {WidgetState.focused}, pressed = {WidgetState.pressed};
    final phone = flickTheme(), tv = flickTheme(tv: true);
    final stockFocus = FilledButton.styleFrom(foregroundColor: FlickTokens.onAccent).overlayColor!.resolve(focused);

    expect(phone.focusColor, ThemeData(useMaterial3: true, brightness: Brightness.dark).focusColor);
    expect(phone.filledButtonTheme.style!.overlayColor!.resolve(focused), stockFocus);

    expect(tv.focusColor, Colors.transparent);
    for (final style in [
      tv.filledButtonTheme.style!,
      tv.outlinedButtonTheme.style!,
      tv.textButtonTheme.style!,
      tv.iconButtonTheme.style!,
    ]) {
      expect(style.overlayColor!.resolve(focused), Colors.transparent);
    }
    expect(tv.filledButtonTheme.style!.overlayColor!.resolve(pressed),
        phone.filledButtonTheme.style!.overlayColor!.resolve(pressed));
  });
}
