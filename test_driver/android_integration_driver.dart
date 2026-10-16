import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      // SCREENSHOT_DIR keeps iOS runs from overwriting Android evidence.
      final dir = Platform.environment['SCREENSHOT_DIR'] ?? 'output/releases';
      final file = File('$dir/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return true;
    },
  );
}
