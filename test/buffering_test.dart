import 'package:flick/screens/buffering.dart';
import 'package:flick/stall.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BufferView view(BufferPhase phase,
        {double? progress, ({int peers, int? rate})? stats, bool offer = false}) =>
    (phase: phase, progress: progress, stats: stats, offerSwitch: offer);

Future<void> pump(WidgetTester tester, BufferView v,
    {VoidCallback? onSwitch, double textScale = 1, bool reduce = false,
      bool settle = true, String? logo, String? poster, bool waiting = false}) async {
  await tester.binding.setSurfaceSize(const Size(640, 360)); // the player is landscape-only
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: flickTheme(),
    home: MediaQuery(
      data: MediaQueryData(
          size: const Size(640, 360),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduce),
      child: Scaffold(body: BufferingPanel(view: v, title: 'The Movie',
        logo: logo, poster: poster, waiting: waiting, onSwitch: onSwitch ?? () {})),
    ),
  ));
  if (settle) await tester.pumpAndSettle();
}

Finder get revealClip => find.descendant(of: find.byType(ArtworkProgress),
  matching: find.byWidgetPredicate((widget) => widget is ClipRect && widget.clipper != null));

Rect reveal(WidgetTester tester) => tester.widget<ClipRect>(revealClip).clipper!
  .getClip(tester.getSize(revealClip));

double revealFraction(WidgetTester tester) => reveal(tester).width / tester.getSize(revealClip).width;

void main() {
  testWidgets('artwork reveals exact widths, clamps progress and keeps a translucent base', (tester) async {
    for (final (progress, fraction) in [
      (null, 0.0), (-1.0, 0.0), (0.0, 0.0), (0.5, 0.5), (1.0, 1.0), (2.0, 1.0),
      (double.nan, 0.0),
    ]) {
      await pump(tester, view(BufferPhase.starting, progress: progress), reduce: true);
      final size = tester.getSize(revealClip);
      expect(tester.getSize(find.byType(ArtworkProgress)), const Size(272, 72));
      expect(reveal(tester), Rect.fromLTWH(0, 0, size.width * fraction, size.height));
      expect(tester.widget<Opacity>(find.descendant(of: find.byType(ArtworkProgress),
        matching: find.byType(Opacity))).opacity, 0.25);
      expect(find.text('The Movie'), findsNWidgets(2));
    }
  });

  testWidgets('logo falls back to cover and then title text on image errors', (tester) async {
    await pump(tester, view(BufferPhase.starting), settle: false,
      logo: 'https://images.example/logo.png', poster: 'https://images.example/cover.jpg');
    final image = tester.widgetList<Image>(find.byType(Image)).first;
    expect((image.image as NetworkImage).url, 'https://images.example/logo.png');
    expect(image.fit, BoxFit.contain);
    final context = tester.element(find.byType(Image).first);
    final cover = image.errorBuilder!(context, Exception('logo unavailable'), null) as Image;
    expect((cover.image as NetworkImage).url, 'https://images.example/cover.jpg');
    final fallback = cover.errorBuilder!(context, Exception('cover unavailable'), null) as Stack;
    expect(((fallback.children.first as Opacity).child as Text).data, 'The Movie');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('a narrow decoded cover reveals across its own width without stretching', (tester) async {
    await pump(tester, view(BufferPhase.starting, progress: 0.5), reduce: true,
      settle: false, poster: 'https://images.example/narrow-cover.jpg');
    final image = tester.widget<Image>(find.byType(Image));
    final artwork = image.frameBuilder!(tester.element(find.byType(Image)),
      const RawImage(width: 24, height: 72), 0, true);
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(
      width: 272, height: 72, child: Center(child: artwork)))));
    final finder = find.byWidgetPredicate((widget) => widget is ClipRect && widget.clipper != null);
    expect(tester.getSize(finder), const Size(24, 72));
    expect(tester.widget<ClipRect>(finder).clipper!.getClip(tester.getSize(finder)),
      const Rect.fromLTWH(0, 0, 12, 72));
  });

  testWidgets('offline retains the last measured fill', (tester) async {
    await pump(tester, view(BufferPhase.stalled, progress: 0.5));
    await pump(tester, bufferView(started: true, buffering: true,
      waited: const Duration(seconds: 2), percent: 90, lastProgress: 0.5,
      online: false, repeatedStalls: false));
    expect(revealFraction(tester), 0.5);
  });

  testWidgets('successful resume reveals fully before fading and disables its action immediately', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pump(tester, view(BufferPhase.stalled, progress: 0.5, offer: true), onSwitch: () => taps++);
    await pump(tester, view(BufferPhase.hidden), settle: false);
    expect(find.byType(ArtworkProgress), findsOneWidget);
    expect(tester.getSemantics(find.byType(Scaffold)).toStringDeep(),
      isNot(contains('Try another source')));
    await tester.tap(find.text('Try another source'), warnIfMissed: false);
    expect(taps, 0);
    await tester.pump();
    await tester.pump(FlickTokens.artworkFadeDuration);
    expect(revealFraction(tester), 1);
    await tester.pump(FlickTokens.stateDuration);
    expect(find.byType(ArtworkProgress), findsNothing);
    semantics.dispose();
  });

  testWidgets('a new stall cancels completion and fade; removal cancels timers', (tester) async {
    for (final elapsed in [const Duration(milliseconds: 60), const Duration(milliseconds: 220)]) {
      await pump(tester, view(BufferPhase.stalled, progress: 0.5));
      await pump(tester, view(BufferPhase.hidden), settle: false);
      await tester.pump(elapsed);
      await pump(tester, view(BufferPhase.stalled, progress: 0.2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Buffering'), findsOneWidget);
      expect(revealFraction(tester), closeTo(0.2, 0.001));
    }
    await pump(tester, view(BufferPhase.hidden), settle: false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion completes and removes the panel immediately', (tester) async {
    await pump(tester, view(BufferPhase.stalled, progress: 0.5), reduce: true);
    await pump(tester, view(BufferPhase.hidden), reduce: true, settle: false);
    expect(find.byType(ArtworkProgress), findsNothing);
  });

  testWidgets('a suppressed new stall cancels completion without flashing its panel', (tester) async {
    await pump(tester, view(BufferPhase.stalled, progress: 0.5));
    await pump(tester, view(BufferPhase.hidden), settle: false);
    await tester.pump(const Duration(milliseconds: 60));
    await pump(tester, view(BufferPhase.hidden), waiting: true, settle: false);
    expect(find.byType(ArtworkProgress), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    await pump(tester, view(BufferPhase.stalled, progress: 0.2), waiting: true);
    expect(revealFraction(tester), closeTo(0.2, 0.001));
  });

  testWidgets('status and artwork taps pass through to the video controls', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Stack(children: [
      Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque,
        onTap: () => taps++)),
      BufferingPanel(view: view(BufferPhase.stalled), title: 'The Movie', onSwitch: () {}),
    ]))));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(ArtworkProgress)));
    await tester.tapAt(tester.getCenter(find.text('Buffering')));
    expect(taps, 2);
  });

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
    for (final reduce in [false, true]) {
      await pump(tester, view(BufferPhase.offline, offer: true), textScale: 1.3, reduce: reduce);
      expect(tester.takeException(), isNull);
      // The card itself, not BufferingPanel (which fills the screen to place the card).
      final card = tester.getRect(find.descendant(
          of: find.byType(BufferingPanel), matching: find.byType(DecoratedBox)).first);
      expect(card.top, greaterThanOrEqualTo(0));
      expect(card.bottom, lessThanOrEqualTo(360));
      expect(card.width, 320);
    }
  });
}
