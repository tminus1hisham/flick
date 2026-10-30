import 'package:flick/screens/upnext.dart';
import 'package:flick/theme.dart';
import 'package:flick/upnext.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const NextEpisode _episode = (label: 'S1 E3', title: 'Title', thumbnail: 'https://example.invalid/thumb.jpg');

UpNextView _view({bool visible = true, double? countdown, int secondsLeft = 10, bool resolving = false}) =>
    (visible: visible, countdown: countdown, secondsLeft: secondsLeft, resolving: resolving);

Future<void> _pump(WidgetTester tester, Widget child, {double textScale = 1}) async {
  await tester.binding.setSurfaceSize(const Size(640, 360)); // the player is landscape-only
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: flickTheme(),
    home: MediaQuery(
      data: MediaQueryData(size: const Size(640, 360), textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Padding(
          // Where the player puts it: bottom-right, clear of the 64 dp bar.
          padding: const EdgeInsets.only(right: 12, bottom: 76),
          child: Align(alignment: Alignment.bottomRight, child: child),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400)); // enter motion; the thumbnail fails to its plain tile
}

Widget _card({UpNextView? view, bool autoplay = true, VoidCallback? onNext, VoidCallback? onDismiss,
        ValueChanged<bool>? onAutoplay}) =>
    UpNextCard(
      view: view ?? _view(),
      episode: _episode,
      autoplay: autoplay,
      onNext: onNext ?? () {},
      onDismiss: onDismiss ?? () {},
      onAutoplay: onAutoplay ?? (_) {},
    );

void main() {
  testWidgets('fits 640x360 at 1.3x text with a thumbnail, counting and resolving', (tester) async {
    for (final view in [_view(countdown: 0.4, secondsLeft: 6), _view(), _view(resolving: true, countdown: 1)]) {
      await _pump(tester, _card(view: view), textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.text('Title'), findsOneWidget);
    }
  });

  testWidgets('semantics: one identity node; the Next action names the countdown and resolving', (tester) async {
    final handle = tester.ensureSemantics();
    var taps = 0;
    await _pump(tester, _card(view: _view(countdown: 0.4, secondsLeft: 6), onNext: () => taps++));
    expect(find.bySemanticsLabel('Up next, S1 E3, Title'), findsOneWidget);
    expect(find.bySemanticsLabel('Next episode in 6 seconds'), findsOneWidget);

    await _pump(tester, _card(onNext: () => taps++));
    expect(find.bySemanticsLabel('Next episode'), findsOneWidget);
    await tester.tap(find.text('Next episode'));
    expect(taps, 1);

    await _pump(tester, _card(view: _view(resolving: true, countdown: 1), onNext: () => taps++));
    final resolving = find.bySemanticsLabel('Finding next episode…');
    expect(resolving, findsOneWidget);
    expect(tester.getSemantics(resolving), isSemantics(isButton: true, hasEnabledState: true, isEnabled: false));
    await tester.tap(find.text('Finding next episode…'), warnIfMissed: false);
    expect(taps, 1, reason: 'disabled while resolving');
    handle.dispose();
  });

  testWidgets('a hidden card takes no taps', (tester) async {
    var taps = 0;
    await _pump(tester, _card(view: _view(visible: false), onNext: () => taps++));
    await tester.tap(find.text('Next episode'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('Watch credits dismisses; the Autoplay control flips the setting', (tester) async {
    var dismissed = 0;
    final autoplay = <bool>[];
    await _pump(tester, _card(onDismiss: () => dismissed++, onAutoplay: autoplay.add));
    await tester.tap(find.text('Watch credits'));
    expect(dismissed, 1);
    await tester.tap(find.text('Autoplay'));
    expect(autoplay, [false]);

    await _pump(tester, _card(autoplay: false, onAutoplay: autoplay.add));
    await tester.tap(find.byType(Switch));
    expect(autoplay, [false, true]);
  });

  testWidgets('NextEpisodeButton fires when enabled, not when null', (tester) async {
    var taps = 0;
    await _pump(tester, NextEpisodeButton(onPressed: () => taps++));
    await tester.tap(find.text('Next episode'));
    expect(taps, 1);
    await _pump(tester, const NextEpisodeButton(onPressed: null));
    await tester.tap(find.text('Next episode'), warnIfMissed: false);
    expect(tester.takeException(), isNull);
    expect(taps, 1);
  });
}
