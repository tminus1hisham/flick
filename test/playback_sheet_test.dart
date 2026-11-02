import 'package:flick/kit/sidebar.dart';
import 'package:flick/screens/movie_queue.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() { device.tv = false; });

  for (final landscape in [false, true]) {
    testWidgets('mobile queue drags, scrolls, collapses and dismisses in ${landscape ? 'landscape' : 'portrait'}', (tester) async {
      tester.view.physicalSize = landscape ? const Size(800, 360) : const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final trigger = FocusNode();
      addTearDown(trigger.dispose);
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, theme: flickTheme(),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(1.3), disableAnimations: true), child: child!),
        home: Builder(builder: (context) => Scaffold(body: TextButton(focusNode: trigger,
          autofocus: true, onPressed: () => showPlaybackSidebar<void>(context, (_) => Column(children: [
            const Text('Queue header'),
            Expanded(child: ListView(primary: true, itemExtent: 64,
              children: [for (var i = 0; i < 40; i++) Text('Movie $i')])),
          ])), child: const Text('Open queue'))))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open queue'));
      await tester.pumpAndSettle();
      final sheet = find.byType(DraggableScrollableSheet);
      final controller = tester.widget<DraggableScrollableSheet>(sheet).controller!;
      final handle = find.bySemanticsLabel('Resize playback queue');
      expect(controller.size, tester.widget<DraggableScrollableSheet>(sheet).initialChildSize);
      await tester.drag(handle, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(controller.size, 1);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('Movie 0').hitTestable(), findsNothing);
      expect(find.text('Queue header').hitTestable(), findsOneWidget);
      await tester.drag(handle, const Offset(0, 400));
      await tester.pumpAndSettle();
      if (sheet.evaluate().isNotEmpty) {
        expect(controller.size, tester.widget<DraggableScrollableSheet>(sheet).minChildSize);
        await tester.drag(handle, const Offset(0, 100));
        await tester.pumpAndSettle();
      }
      expect(sheet, findsNothing);
      expect(trigger.hasFocus, isTrue);
      expect(tester.takeException(), isNull);

      // The actual movie screen uses the sheet's primary controller too.
      showPlaybackSidebar<void>(key.currentContext!, (_) => const MovieQueueScreen());
      await tester.pumpAndSettle();
      expect(tester.widget<ListView>(find.byType(ListView)).primary, isTrue);
      expect(find.text('Playback queue').hitTestable(), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(MovieQueueScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TV keeps the right sidebar without a draggable sheet', (tester) async {
    device.tv = true;
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: key, theme: flickTheme(tv: true), home: const Scaffold()));
    showPlaybackSidebar<void>(key.currentContext!, (_) => const Text('TV queue'));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(tester.getRect(find.text('TV queue')).right, tester.view.physicalSize.width / tester.view.devicePixelRatio);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('TV queue'), findsNothing);
  });
}
