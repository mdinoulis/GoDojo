import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:katago_engine/katago_engine.dart';

import 'mobile_engine.dart';
import 'settings.dart';

enum EngineStatus { stopped, starting, ready, error }

/// Owns the single on-device engine instance and (re)starts it on demand
/// whenever its configuration changes.
class EngineService extends ChangeNotifier {
  KataGoEngine? _engine;
  String? _configKey;
  Future<KataGoEngine>? _starting;
  EngineStatus status = EngineStatus.stopped;
  String? error;

  /// Searches upwards from the executable for the repo's `engine/` folder
  /// (development builds on the PC), or uses $GODOJO_ENGINE_DIR.
  static String? detectDesktopEngineDir() {
    final env = Platform.environment['GODOJO_ENGINE_DIR'];
    if (env != null && Directory(env).existsSync()) return env;
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 10; i++) {
      final candidate = Directory('${dir.path}${Platform.pathSeparator}engine');
      if (File('${candidate.path}/windows/katago.exe').existsSync() ||
          File('${candidate.path}/katago').existsSync()) {
        return candidate.path;
      }
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
    return null;
  }

  static Future<EngineConfig?> resolveConfig(AppSettings s) async {
    EngineConfig? base;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dir = s.engineDir ?? detectDesktopEngineDir();
      if (dir == null) return null;
      base = EngineConfig.desktop(dir.replaceAll('\\', '/'));
    } else if (Platform.isAndroid || Platform.isIOS) {
      base = await MobileEngine.config();
    }
    if (base == null) return null;
    final o = s.engineOverride;
    if (o == null || o.isEmpty) return base;
    return EngineConfig.fromJson({...base.toJson(), ...o});
  }

  /// Returns a running engine for the current settings.
  Future<KataGoEngine> engineFor(AppSettings settings) async {
    final config = await resolveConfig(settings);
    if (config == null) {
      _setError('KataGo was not found. Set the engine folder in Settings.');
      throw StateError(error!);
    }
    final key = jsonEncode(config.toJson());
    if (_engine != null && _configKey == key && _engine!.isRunning) {
      return _engine!;
    }
    if (_starting != null && _configKey == key) return _starting!;
    _configKey = key;
    _starting = _start(config);
    try {
      return await _starting!;
    } finally {
      _starting = null;
    }
  }

  Future<KataGoEngine> _start(EngineConfig config) async {
    await _engine?.stop();
    _engine = null;
    status = EngineStatus.starting;
    error = null;
    notifyListeners();
    try {
      final e = KataGoEngine(config,
          transportFactory: MobileEngine.isSupported ? MobileEngine.transport : null);
      await e.start();
      _engine = e;
      status = EngineStatus.ready;
      notifyListeners();
      return e;
    } catch (e) {
      _configKey = null;
      _setError('Could not start KataGo: $e');
      rethrow;
    }
  }

  void _setError(String msg) {
    status = EngineStatus.error;
    error = msg;
    notifyListeners();
  }

  Future<void> cancel() async => _engine?.cancelAll();

  Future<void> shutdown() async {
    await _engine?.stop();
    _engine = null;
    status = EngineStatus.stopped;
  }

  @override
  void dispose() {
    _engine?.stop();
    super.dispose();
  }
}

final engineServiceProvider = Provider<EngineService>((ref) {
  final s = EngineService();
  ref.onDispose(s.dispose);
  return s;
});
