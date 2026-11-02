import 'package:flick/downloads.dart';
import 'package:flick/screens/downloads.dart';
import 'package:flick/state.dart';
import 'package:flick/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Downloads extends Downloads {
  bool fail = false;
  @override
  Future<void> refreshEnvironment() async {
    storedBytes = 1 << 30;
    freeBytes = 2 << 30;
    notifyListeners();
  }
  @override
  Future<void> setWifiOnly(bool on) async {
    if (fail) throw StateError('could not save');
    wifiOnly = on;
    networkAllowed = !on;
    notifyListeners();
  }
}

void main() {
  for (final tv in [false, true]) {
    testWidgets('download controls work on ${tv ? 'TV' : 'phone'} with large text and an empty list', (tester) async {
      final old = downloads;
      final manager = _Downloads();
      downloads = manager;
      device.tv = tv;
      addTearDown(() { downloads = old; device.tv = false; manager.dispose(); });
      tester.view.physicalSize = tv ? const Size(960, 540) : const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: flickTheme(tv: tv),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.3)), child: child!),
        home: const Scaffold(body: DownloadsScreen()),
      ));
      await tester.pump();
      expect(find.text('Download files: 1.00 GB · Free: 2.00 GB'), findsOneWidget);
      expect(find.text('Wi-Fi only: Off'), findsOneWidget);
      if (tv) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(find.text('Wi-Fi only: Off'));
      }
      await tester.pump();
      expect(manager.wifiOnly, isTrue);
      expect(find.text('Downloads waiting for Wi-Fi or an unmetered network.'), findsOneWidget);
      manager.fail = true;
      await tester.tap(find.text('Wi-Fi only: On'));
      await tester.pump();
      expect(find.text('Could not change the network choice. Try again.'), findsOneWidget);
      expect(manager.wifiOnly, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
