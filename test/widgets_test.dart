import 'dart:io';

import 'package:flick/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friendlyError turns network failures into a sentence', () {
    expect(friendlyError(const SocketException('down')), contains("Can't reach your server"));
  });
}
