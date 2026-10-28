import 'dart:io';

import 'package:flick/jellyfin.dart';
import 'package:flick/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friendlyError turns server and network failures into sentences', () {
    expect(friendlyError(JellyfinException(400, '/Users/AuthenticateByName')), 'Wrong username or password.');
    expect(friendlyError(JellyfinException(401, '/Users/AuthenticateByName')), 'Wrong username or password.');
    expect(friendlyError(JellyfinException(401, '/UserViews')), contains('session has expired'));
    expect(friendlyError(JellyfinException(503, '/UserViews')), contains('error 503'));
    expect(friendlyError(const SocketException('down')), contains("Can't reach your server"));
  });
}
