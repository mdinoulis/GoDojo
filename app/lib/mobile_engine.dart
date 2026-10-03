import 'dart:io';

import 'package:katago_engine/katago_engine.dart';

/// On-device engine setup for phones (filled in by the Android/iOS phases).
class MobileEngine {
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static Future<EngineConfig?> config() async => null;

  static Future<EngineTransport> transport(EngineConfig c) =>
      ProcessTransport.start(c.executable, c.arguments,
          workingDirectory: c.workingDirectory);
}
