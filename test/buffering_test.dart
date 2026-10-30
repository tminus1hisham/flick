import 'package:flick/screens/buffering.dart';
import 'package:flick/stall.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BufferView view(BufferPhase phase,
        {double? progress, ({int peers, int? rate})? stats, bool offer = false}) =>
    (phase: phase, progress: progress, stats: stats, offerSwitch: offer);

Future<void> pump(WidgetTester tester, BufferView v,
    {VoidCallback? onSwitch, double textScale = 1, bool reduce = false}) async {
  await tester.binding.setSurfaceSize(const Size(640, 360)); // the player is landscape-only
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: flickTheme(),
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(640, 360),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduce),
      child: Scaffold(body: BufferingPanel(view: v, onSwitch: onSwitch ?? () {})),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each phase names itself', (tester) async {
    await pump(tester, view(BufferPhase.starting));
    expect(find.text('Starting playback'), findsOneWidget);
    await pump(tester, view(BufferPhase.stalled));
    expect(find.text('Buffering'), findsOneWidget);
    await pump(tester, view(BufferPhase.offline));
    expect(find.text('Waiting for connection'), findsOneWidget);
    expect(find.text('Playback will resume automatically.'), findsOneWidget);
  });

  testWidgets('stats: peers and fresh rate; rate dropped when stale; one peer', (tester) async {
    await pump(tester, view(BufferPhase.stalled, stats: (peers: 6, rate: 3 << 19)));
    expect(find.textContaining('6 peers · 1.5 MB/s', findRichText: true), findsOneWidget);
    await pump(tester, view(BufferPhase.stalled, stats: (peers: 1, rate: null)));
    expect(find.textContaining('1 peer', findRichText: true), findsOneWidget);
    expect(find.textContaining('1 peers', findRichText: true), findsNothing);
    expect(find.textContaining('MB/s', findRichText: true), findsNothing);
  });

  testWidgets('offline hides stats', (tester) async {
    await pump(tester, view(BufferPhase.offline, stats: (peers: 6, rate: 1 << 20)));
    expect(find.textContaining('peers', findRichText: true), findsNothing);
  });

  testWidgets('switch action: 48 dp, taps through, absent from semantics when not offered',
      (tester) async {
    var taps = 0;
    await pump(tester, view(BufferPhase.stalled, offer: true), onSwitch: () => taps++);
    final button = find.widgetWithText(OutlinedButton, 'Try another source');
    expect(tester.getSize(button).height, greaterThanOrEqualTo(FlickTokens.minTouchTarget));
    await tester.tap(button);
    expect(taps, 1);

    await pump(tester, view(BufferPhase.stalled));
    expect(find.text('Try another source'), findsNothing);
    expect(find.bySemanticsLabel('Try another source'), findsNothing);
  });

  testWidgets('hidden panel leaves the tree after its fade', (tester) async {
    await pump(tester, view(BufferPhase.stalled));
    await pump(tester, view(BufferPhase.hidden));
    expect(find.text('Buffering'), findsNothing);
  });

  testWidgets('fits 640x360 at 1.3x text, also with reduced motion', (tester) async {
    await pump(tester, view(BufferPhase.offline, offer: true), textScale: 1.3, reduce: true);
    expect(tester.takeException(), isNull);
    final panel = tester.getRect(find.byType(BufferingPanel));
    expect(panel.height, lessThanOrEqualTo(360));
  });
}
