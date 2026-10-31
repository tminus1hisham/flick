import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flick/kit/focus.dart';
import 'package:flick/player_keys.dart';
import 'package:flick/screens/tv_player.dart';
import 'package:flick/screens/upnext.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flick/stall.dart';

class _Harness extends StatefulWidget {
  const _Harness({super.key, this.duration = const Duration(minutes: 10), this.waiting = false});
  final Duration duration;
  final bool waiting;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool playing = true, panel = false, next = false, languages = false;
  late bool waiting = widget.waiting;
  String? error;
  int toggles = 0, exits = 0, retry = 0, nextCalls = 0, closes = 0;
  final seeks = <Duration>[];
  void showNext(bool value) => setState(() => next = value);
  void wait() => setState(() => waiting = true);
  void fail() => setState(() => error = 'Failed');
  void pause() => setState(() => playing = false);
  @override
  Widget build(BuildContext context) => Scaffold(body: TvPlayerControls(
    title: 'Flash Gordon', subtitle: 'S1 E2 · The Tunnel of Terror',
    position: const Duration(minutes: 2), duration: widget.duration, buffer: const Duration(minutes: 3),
    playing: playing, panel: panel, error: error,
    buffering: (phase: waiting ? BufferPhase.offline : BufferPhase.hidden, progress: null, stats: null, offerSwitch: waiting),
    onToggle: () => setState(() { playing = !playing; toggles++; }),
    onSeek: seeks.add, onExit: () => exits++, onRetry: () => retry++,
    onTracks: () => setState(() => panel = true), onCloseTracks: () => setState(() { closes++; if (languages) { languages = false; } else { panel = false; } }),
    onNext: () => nextCalls++, upNextVisible: next,
    upNext: UpNextCard(view: (visible: next, countdown: null, secondsLeft: 10, resolving: false),
      episode: (label: 'S1 E3', title: 'Captured by Shark Men', thumbnail: null),
      autoplay: false, onNext: () => nextCalls++, onDismiss: () => showNext(false), onAutoplay: (_) {}),
    tracks: ListView(padding: const EdgeInsets.all(10), children: [
      const Text('Subtitles & audio', style: FlickTv.railHeading),
      InitialFocus(child: FocusFrame.button(semanticLabel: 'Off', onActivate: () {},
        child: const Padding(padding: EdgeInsets.all(12), child: Text('Off')))),
      const SizedBox(height: 16),
      FocusFrame.button(semanticLabel: 'English', onActivate: () {},
        child: const Padding(padding: EdgeInsets.all(12), child: Text('English'))),
    ]),
  ));
}

void main() {
  tearDown(() {
    device.tv = false;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });
  test('key map separates hidden keys, bar traversal, panel keys and repeat activation', () {
    TvPlayerCommand command(LogicalKeyboardKey key, {bool bar = false, bool panel = false, bool repeat = false}) =>
      tvPlayerKey(key, bar: bar, panel: panel, repeat: repeat);
    expect(command(LogicalKeyboardKey.select), TvPlayerCommand.toggle);
    expect(command(LogicalKeyboardKey.select, repeat: true), TvPlayerCommand.none);
    expect(command(LogicalKeyboardKey.arrowRight), TvPlayerCommand.forward);
    expect(command(LogicalKeyboardKey.arrowRight, bar: true), TvPlayerCommand.none);
    expect(command(LogicalKeyboardKey.arrowRight, panel: true), TvPlayerCommand.none);
    expect(command(LogicalKeyboardKey.arrowDown, bar: true), TvPlayerCommand.hide);
    expect(command(LogicalKeyboardKey.escape), TvPlayerCommand.exit);
    expect(command(LogicalKeyboardKey.escape, bar: true), TvPlayerCommand.hide);
    expect(command(LogicalKeyboardKey.escape, panel: true), TvPlayerCommand.closeTracks);
    expect(command(LogicalKeyboardKey.mediaPlayPause, panel: true), TvPlayerCommand.toggle);
  });
  test('seek clamps before EOF, accelerates after one second, and refuses unknown duration', () {
    const position = Duration(seconds: 45), duration = Duration(seconds: 60);
    expect(tvSeek(position, duration, forward: true), const Duration(seconds: 55));
    expect(tvSeek(position, duration, forward: true, held: const Duration(seconds: 1)), const Duration(seconds: 59));
    expect(tvSeek(Duration.zero, duration, forward: false), Duration.zero);
    expect(tvSeek(position, const Duration(milliseconds: 500), forward: true), Duration.zero);
    expect(tvSeek(position, Duration.zero, forward: true), isNull);
    expect(playerTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(playerTime(const Duration(seconds: -1)), '0:00');
  });

  Future<GlobalKey<_HarnessState>> pump(WidgetTester tester, {Duration duration = const Duration(minutes: 10),
      Size size = const Size(960, 540), double scale = 1, bool waiting = false}) async {
    device.tv = true;
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final harness = GlobalKey<_HarnessState>();
    await tester.pumpWidget(MaterialApp(theme: flickTheme(tv: true), shortcuts: tvShortcuts,
      home: _Harness(key: harness, duration: duration, waiting: waiting)));
    await tester.pumpAndSettle();
    return harness;
  }
  String? focused() => FocusManager.instance.primaryFocus?.context
      ?.findAncestorWidgetOfExactType<FocusFrame>()?.semanticLabel;
  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key); await tester.pumpAndSettle();
  }
  Future<void> back(WidgetTester tester) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage('flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')), (_) {});
    await tester.pumpAndSettle();
  }

  testWidgets('hidden Select toggles once and focuses Play; bar arrows traverse without seeking', (tester) async {
    final h = await pump(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player keys');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(h.currentState!.toggles, 1);
    expect(focused(), 'Play');
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(h.currentState!.toggles, 1);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Subtitles');
    expect(h.currentState!.seeks, isEmpty);
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player keys');
  });

  testWidgets('hidden Left/Right seeks with immediate position feedback, unknown duration shows bar', (tester) async {
    final h = await pump(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(h.currentState!.seeks, [const Duration(minutes: 2, seconds: 10)]);
    expect(find.text('Seeking 2:10'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(h.currentState!.seeks.last, const Duration(minutes: 2));
    await tester.pumpWidget(const SizedBox());
    final unknown = await pump(tester, duration: Duration.zero);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(unknown.currentState!.seeks, isEmpty);
    expect(focused(), 'Pause');
  });

  testWidgets('bar auto-hides after four seconds playing, and stays while paused', (tester) async {
    final h = await pump(tester);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'Pause');
    await tester.pump(const Duration(seconds: 4)); await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player keys');
    await key(tester, LogicalKeyboardKey.arrowUp);
    h.currentState!.pause(); await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(focused(), 'Play');
  });

  testWidgets('tracks trap arrows, select current row, and system Back returns to Subtitles', (tester) async {
    final h = await pump(tester);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    expect(h.currentState!.panel, isTrue);
    expect(focused(), 'Off');
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'Off');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'Off');
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Off');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'English');
    await tester.pump(const Duration(seconds: 8));
    expect(focused(), 'English');
    await back(tester);
    expect(h.currentState!.panel, isFalse);
    expect(focused(), 'Subtitles');
    await back(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player keys');
  });

  testWidgets('Android Back key and navigation event close only one layer', (tester) async {
    final h = await pump(tester);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    h.currentState!.languages = true;
    final layer = tester.widgetList<Focus>(find.byType(Focus)).firstWhere((f) => f.focusNode?.debugLabel == 'Player keys');
    layer.onKeyEvent!(layer.focusNode!, const KeyDownEvent(physicalKey: PhysicalKeyboardKey.escape,
      logicalKey: LogicalKeyboardKey.goBack, timeStamp: Duration.zero));
    await back(tester);
    expect(h.currentState!.closes, 1);
    expect(h.currentState!.panel, isTrue);
  });

  testWidgets('Up Next never steals focus; Up reaches card and its disappearance restores Play', (tester) async {
    final h = await pump(tester);
    h.currentState!.showNext(true); await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player keys');
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(focused(), 'Subtitles');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<UpNextCard>(), isNotNull);
    await tester.pump(const Duration(seconds: 8));
    expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<UpNextCard>(), isNotNull);
    h.currentState!.showNext(false); await tester.pumpAndSettle();
    expect(focused(), 'Pause');
  });


  testWidgets('played and buffered rails have visible height and advance proportionally', (tester) async {
    await pump(tester);
    await key(tester, LogicalKeyboardKey.arrowUp);
    final rail = find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '2:00 of 10:00');
    final played = find.descendant(of: rail,
      matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == FlickTokens.activeMarker));
    final buffered = find.descendant(of: rail,
      matching: find.byWidgetPredicate((w) => w is ColoredBox && w.color == FlickTokens.textSecondary));
    expect(tester.getSize(played).height, greaterThan(0));
    expect(tester.getSize(played).width, closeTo(tester.getSize(rail).width * .2, .1));
    expect(tester.getSize(buffered).height, greaterThan(0));
    expect(tester.getSize(buffered).width, greaterThan(tester.getSize(played).width));
  });

  testWidgets('offered recovery on entry focuses and activates source action without toggling playback', (tester) async {
    final h = await pump(tester, waiting: true);
    expect(focused(), 'Try another source');
    await key(tester, LogicalKeyboardKey.select);
    expect(h.currentState!.exits, 1);
    expect(h.currentState!.toggles, 0);
  });

  testWidgets('late offline state keeps valid focus; recovery is reachable from the bar', (tester) async {
    final h = await pump(tester);
    h.currentState!.wait(); await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player keys');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'Pause');
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(focused(), 'Try another source');
    await tester.pump(const Duration(seconds: 8));
    expect(focused(), 'Try another source');
    await key(tester, LogicalKeyboardKey.arrowDown);
    expect(focused(), 'Pause');
  });

  testWidgets('fatal recovery focuses Retry and activates it by remote', (tester) async {
    final h = await pump(tester);
    h.currentState!.fail(); await tester.pumpAndSettle();
    expect(focused(), 'Retry');
    await key(tester, LogicalKeyboardKey.select);
    expect(h.currentState!.retry, 1);
  });

  testWidgets('controls, Up Next and tracks fit 900x500 at 1.3x text', (tester) async {
    final h = await pump(tester, size: const Size(900, 500), scale: 1.3);
    h.currentState!.showNext(true); await tester.pumpAndSettle();
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(tester.takeException(), isNull);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.select);
    expect(focused(), 'Off');
    expect(tester.takeException(), isNull);
  });
}

