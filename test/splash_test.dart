import 'package:flick/theme.dart';
import 'package:flick/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const Text('Home');
}

Widget _app({bool reduceMotion = false, Key? probe}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: SplashHandoff(child: child!),
      ),
      home: _Probe(key: probe),
    );

void main() {
  testWidgets('the splash mark leaves after the handoff and the app keeps its state', (tester) async {
    final probe = GlobalKey<_ProbeState>();
    await tester.pumpWidget(_app(probe: probe));

    expect(find.byType(FlickMark), findsOneWidget);
    expect(tester.getSize(find.byType(FlickMark)), const Size.square(SplashHandoff.markSize));
    final before = probe.currentState;

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FlickMark), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(FlickMark), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(probe.currentState, same(before));
  });

  testWidgets('reduce motion goes straight to the app', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    await tester.pump();

    expect(find.byType(FlickMark), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });
}
