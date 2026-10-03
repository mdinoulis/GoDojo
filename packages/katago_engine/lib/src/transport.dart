import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A line-based, bidirectional channel to an engine (one JSON message per
/// line). Desktop and Android use [ProcessTransport]; iOS uses an in-process
/// FFI transport because subprocesses are not allowed there.
abstract class EngineTransport {
  Stream<String> get lines;
  void send(String line);

  /// Completes when the engine has loaded its networks and accepts queries.
  Future<void> get ready;

  /// Completes when the engine exits (with its exit code, if known).
  Future<int?> get done;

  Future<void> close();
}

class EngineStartException implements Exception {
  final String message;
  final String log;
  EngineStartException(this.message, this.log);
  @override
  String toString() => 'EngineStartException: $message\n$log';
}

/// Runs the engine as a child process speaking over stdin/stdout.
class ProcessTransport implements EngineTransport {
  final Process _process;
  final _lines = StreamController<String>.broadcast();
  final _ready = Completer<void>();
  final _log = <String>[];

  ProcessTransport._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_lines.add, onDone: _lines.close);
    _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((l) {
      _log.add(l);
      if (_log.length > 200) _log.removeAt(0);
      if (!_ready.isCompleted && l.contains('ready to begin handling requests')) {
        _ready.complete();
      }
    });
    _process.exitCode.then((code) {
      if (!_ready.isCompleted) {
        _ready.completeError(
            EngineStartException('Engine exited with code $code', recentLog));
      }
    });
  }

  static Future<ProcessTransport> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Duration startupTimeout = const Duration(minutes: 3),
  }) async {
    final p = await Process.start(executable, arguments,
        workingDirectory: workingDirectory);
    final t = ProcessTransport._(p);
    final timer = Timer(startupTimeout, () {
      if (!t._ready.isCompleted) {
        t._ready.completeError(EngineStartException(
            'Engine did not become ready within $startupTimeout', t.recentLog));
        p.kill();
      }
    });
    t._ready.future.whenComplete(timer.cancel).ignore();
    return t;
  }

  /// Last lines the engine wrote to stderr (useful for error reports).
  String get recentLog => _log.join('\n');

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> get ready => _ready.future;

  @override
  Future<int?> get done => _process.exitCode;

  @override
  void send(String line) => _process.stdin.writeln(line);

  @override
  Future<void> close() async {
    try {
      await _process.stdin.close();
    } catch (_) {}
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _process.kill();
      return -1;
    });
  }
}
