import 'package:flick/pip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flick/pip');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'supported' || 'enter' => true,
        _ => null,
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Future<void> native(String method, [Object? arguments]) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, arguments),
      ),
      (_) {},
    );
  }

  test(
    'PiP callbacks hide controls, restore them, and pause on stop',
    () async {
      var stops = 0, updates = 0;
      final pip = PictureInPicture(onStop: () => stops++);
      pip.addListener(() => updates++);
      await pip.init();
      expect(pip.supported, isTrue);
      await pip.playing(true);
      expect(calls.last.arguments, isTrue);
      expect(await pip.enter(), isTrue);
      await native('changed', true);
      expect(pip.active, isTrue);
      await native('changed', false);
      expect(pip.active, isFalse);
      await native('stopped');
      expect(stops, 1);
      expect(updates, 3);
      pip.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.method, 'playing');
      expect(calls.last.arguments, isFalse);
    },
  );

  test('unsupported platforms and denied entry fail gracefully', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    final pip = PictureInPicture(onStop: () {});
    await pip.init();
    expect(pip.supported, isFalse);
    expect(await pip.enter(), isFalse);
    pip.dispose();
  });

  test('disposing an old player leaves the next player connected', () async {
    final old = PictureInPicture(onStop: () {});
    final next = PictureInPicture(onStop: () {});
    await old.init();
    await next.init();
    calls.clear();
    old.dispose();
    await native('changed', true);
    expect(next.active, isTrue);
    expect(calls, isEmpty);
    next.dispose();
  });
}
