import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PictureInPicture extends ChangeNotifier {
  PictureInPicture({required this.onStop});

  static const _channel = MethodChannel('flick/pip');
  static PictureInPicture? _owner;
  final VoidCallback onStop;
  bool supported = false, active = false;
  bool _disposed = false;

  Future<void> init() async {
    _owner = this;
    _channel.setMethodCallHandler((call) async {
      if (_disposed) return;
      if (call.method == 'changed') {
        active = call.arguments == true;
        notifyListeners();
      } else if (call.method == 'stopped') {
        onStop();
      }
    });
    supported = await _invoke<bool>('supported') ?? false;
    if (!_disposed) notifyListeners();
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('Picture-in-picture: $e');
      return null;
    }
  }

  Future<void> playing(bool value) async => _invoke<void>('playing', value);
  Future<bool> enter() async => await _invoke<bool>('enter') ?? false;

  @override
  void dispose() {
    _disposed = true;
    if (_owner == this) {
      _owner = null;
      _channel.setMethodCallHandler(null);
      playing(false);
    }
    super.dispose();
  }
}
