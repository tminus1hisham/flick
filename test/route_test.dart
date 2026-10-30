import 'package:flick/kit/route.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late BuildContext home;

  Future<void> pumpHome(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        theme: flickTheme(),
        home: Builder(builder: (context) {
          home = context;
          return const Text('Stream list');
        }),
      ));

  testWidgets('popForNext leaves without the exit animation; a plain pop animates', (tester) async {
    await pumpHome(tester);
    late BuildContext episode;
    Navigator.push(home, EpisodeRoute<void>(builder: (context) {
      episode = context;
      return const Text('Player');
    }));
    await tester.pumpAndSettle();

    popForNext(episode, 'next');
    await tester.pump();
    await tester.pump();
    expect(find.text('Player'), findsNothing);

    Navigator.push(home, EpisodeRoute<void>(builder: (context) {
      episode = context;
      return const Text('Player');
    }));
    await tester.pumpAndSettle();
    Navigator.pop(episode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Player'), findsOneWidget, reason: 'still on its way out');
    await tester.pumpAndSettle();
  });

  testWidgets('the next episode fades in over the background, hiding the stream list from its first frame',
      (tester) async {
    await pumpHome(tester);
    Navigator.push(home, EpisodeRoute<void>(builder: (_) => const Text('Next'), next: true));
    await tester.pump();
    final cover = tester.widget<ColoredBox>(
        find.ancestor(of: find.byType(FadeTransition), matching: find.byType(ColoredBox)).first);
    expect(cover.color, FlickTokens.background);
    await tester.pump(FlickTokens.artworkFadeDuration);
    expect(find.text('Next'), findsOneWidget);
  });
}
