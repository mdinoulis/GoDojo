import 'dart:io';

import 'package:flutter/services.dart';
import 'package:katago_engine/katago_engine.dart';

import 'ffi_transport.dart';

/// On-device engine for phones. Android runs the KataGo executable shipped
/// as `libkatago.so`; iOS links KataGo into the app and runs it in-process.
/// The networks are copied from the app package on first launch.
class MobileEngine {
  static const _channel = MethodChannel('gostudy/engine');

  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  static Future<EngineConfig?> config() async {
    final libDir = Platform.isAndroid
        ? await _channel.invokeMethod<String>('nativeLibraryDir')
        : 'in-process';
    final dataDir = await _channel.invokeMethod<String>('installEngineFiles');
    if (libDir == null || dataDir == null) return null;
    final files = Directory(dataDir)
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .toList();
    String? find(bool Function(String name) test) {
      for (final f in files) {
        final name = f.split(Platform.pathSeparator).last;
        if (test(name)) return f;
      }
      return null;
    }

    final human = find((n) => n.contains('human') && n.endsWith('.gz'));
    final main = find((n) => !n.contains('human') && n.endsWith('.gz'));
    final cfg = find((n) => n.endsWith('.cfg'));
    if (main == null || cfg == null) return null;
    return EngineConfig(
      executable: '$libDir/libkatago.so',
      model: main,
      humanModel: human,
      configFile: cfg,
      workingDirectory: dataDir,
      // Phone CPUs are much slower than a desktop GPU.
      hintVisits: 150,
      rateVisits: 120,
      estimateVisits: 100,
      reviewVisits: 40,
      botSearchVisits: 12,
      fullStrengthVisits: 200,
    );
  }

  static Future<EngineTransport> transport(EngineConfig c) {
    if (Platform.isIOS) {
      // KataGo resolves relative paths (logs) against the working directory.
      Directory.current = c.workingDirectory!;
      return FfiTransport.start(c.arguments);
    }
    return ProcessTransport.start(c.executable, c.arguments,
        workingDirectory: c.workingDirectory,
        startupTimeout: const Duration(minutes: 5));
  }
}
