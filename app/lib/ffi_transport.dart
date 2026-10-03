import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:katago_engine/katago_engine.dart';

typedef _StartC = Int32 Function(Int32, Pointer<Pointer<Utf8>>);
typedef _StartD = int Function(int, Pointer<Pointer<Utf8>>);
typedef _SendC = Void Function(Pointer<Utf8>);
typedef _SendD = void Function(Pointer<Utf8>);
typedef _CloseC = Void Function();
typedef _CloseD = void Function();
typedef _ReadC = Int32 Function(Pointer<Uint8>, Int32);
typedef _ReadD = int Function(Pointer<Uint8>, int);

/// Runs KataGo inside the app process (iOS - no subprocesses allowed) via the
/// C bridge in engine/ios/katago_bridge.cpp, linked into the app binary.
class FfiTransport implements EngineTransport {
  final DynamicLibrary _lib;
  final _lines = StreamController<String>.broadcast();
  final _ready = Completer<void>();
  final _done = Completer<int?>();
  final _log = <String>[];
  late final _SendD _send = _lib.lookupFunction<_SendC, _SendD>('katago_send_line');
  late final _CloseD _close = _lib.lookupFunction<_CloseC, _CloseD>('katago_close_input');

  FfiTransport._(this._lib);

  static Future<FfiTransport> start(List<String> arguments,
      {DynamicLibrary? library}) async {
    final lib = library ?? DynamicLibrary.process();
    final t = FfiTransport._(lib);
    final start = lib.lookupFunction<_StartC, _StartD>('katago_start');
    final args = ['analysis', ...arguments.skip(1)];
    final argv = calloc<Pointer<Utf8>>(args.length);
    for (var i = 0; i < args.length; i++) {
      argv[i] = args[i].toNativeUtf8();
    }
    final rc = start(args.length, argv);
    for (var i = 0; i < args.length; i++) {
      calloc.free(argv[i]);
    }
    calloc.free(argv);
    if (rc != 0) throw EngineStartException('katago_start failed ($rc)', '');

    // Blocking reads happen on a helper isolate.
    final port = ReceivePort();
    port.listen((msg) => t._onLine(msg as String?, port));
    await Isolate.spawn(_readLoop, port.sendPort);
    return t;
  }

  static void _readLoop(SendPort out) {
    final lib = DynamicLibrary.process();
    final read = lib.lookupFunction<_ReadC, _ReadD>('katago_read_line');
    const cap = 8 << 20; // analysis lines with ownership can be large
    final buf = calloc<Uint8>(cap);
    while (true) {
      final n = read(buf, cap);
      if (n < 0) break;
      out.send(buf.cast<Utf8>().toDartString());
    }
    calloc.free(buf);
    out.send(null);
  }

  void _onLine(String? line, ReceivePort port) {
    if (line == null) {
      port.close();
      _lines.close();
      if (!_done.isCompleted) _done.complete(null);
      if (!_ready.isCompleted) {
        _ready.completeError(EngineStartException('Engine exited', recentLog));
      }
      return;
    }
    if (line.startsWith('#ERR ')) {
      final l = line.substring(5);
      _log.add(l);
      if (_log.length > 200) _log.removeAt(0);
      if (!_ready.isCompleted && l.contains('ready to begin handling requests')) {
        _ready.complete();
      }
      return;
    }
    if (line.startsWith('#EXIT ')) {
      if (!_done.isCompleted) _done.complete(int.tryParse(line.substring(6)));
      return;
    }
    _lines.add(line);
  }

  String get recentLog => _log.join('\n');

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> get ready => _ready.future;

  @override
  Future<int?> get done => _done.future;

  @override
  void send(String line) {
    final p = line.toNativeUtf8();
    _send(p);
    calloc.free(p);
  }

  @override
  Future<void> close() async => _close();
}
