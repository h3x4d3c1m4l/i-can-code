import 'dart:async';
import 'dart:js_interop';

import 'package:i_can_code/services/python/python_assets_web.dart';
import 'package:i_can_code/services/python/python_repl.dart';
import 'package:i_can_code/services/web/absolute_url_web.dart';
import 'package:web/web.dart' as web;

/// Copied verbatim from `web/python/` into the build output.
const String _workerPath = 'python/python_repl_worker.js';
const String _channelPath = 'python/stdin_channel.js';

PythonRepl createPythonRepl() => WebPythonRepl();

/// The module in `web/python/stdin_channel.js`, typed.
///
/// It is reached by `importModule` rather than rewritten in Dart because the
/// worker half has to be the same code, and because `Atomics` has no Dart
/// binding — the page's half is only `write`, `close` and two loads, so keeping
/// the protocol in one file is worth the interop.
extension type _StdinChannelModule(JSObject _) implements JSObject {

  external JSObject createChannel();

  external int write(JSObject channel, String text);

  external void close(JSObject channel);

  external bool isWaiting(JSObject channel);

}

extension type _InitMessage._(JSObject _) implements JSObject {

  external factory _InitMessage({String type, String wasmUrl, String stdlibUrl});

}

extension type _StartMessage._(JSObject _) implements JSObject {

  external factory _StartMessage({String type, JSObject channel});

}

extension type _OutputChunk(JSObject _) implements JSObject {

  external String get kind;
  external String get text;

}

extension type _WorkerMessage(JSObject _) implements JSObject {

  external String get type;
  external JSArray<_OutputChunk>? get chunks;
  external int? get code;
  external String? get message;

}

/// Runs one interactive CPython in a dedicated web worker.
///
/// The worker blocks for the whole session — it parks inside `fd_read` between
/// lines — so it can be sent exactly one message, `start`, and never another.
/// Input goes through the shared buffer instead, and stopping is termination.
class WebPythonRepl implements PythonRepl {

  final StreamController<ReplEvent> _events = StreamController<ReplEvent>.broadcast();

  web.Worker? _worker;
  _StdinChannelModule? _module;
  JSObject? _channel;
  Future<void>? _starting;
  bool _disposed = false;

  @override
  // `SharedArrayBuffer` is absent rather than broken on a page that is not
  // cross-origin isolated, and `Atomics.wait` is the only way to hold CPython
  // inside a read. There is no degraded mode to fall back to.
  bool get isSupported => web.window.crossOriginIsolated;

  @override
  Stream<ReplEvent> get events => _events.stream;

  @override
  bool get isWaitingForInput {
    final module = _module;
    final channel = _channel;
    if (module == null || channel == null) return false;
    return module.isWaiting(channel);
  }

  @override
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    if (!isSupported) {
      _emit(const ReplFailed(
        'This browser cannot run an interactive session: the page is not cross-origin isolated.',
      ));
      return;
    }

    try {
      final module = (await importModule(absoluteUrl(_channelPath).toJS).toDart) as _StdinChannelModule;
      _module = module;
      _channel = module.createChannel();
    } on Object catch (error) {
      _emit(ReplFailed('$error'));
      return;
    }

    final worker = web.Worker(absoluteUrl(_workerPath).toJS, web.WorkerOptions(type: 'module'));
    _worker = worker;

    worker
      ..onmessage = ((web.MessageEvent event) => _onMessage(event.data! as _WorkerMessage)).toJS
      ..onerror = ((web.ErrorEvent event) {
        _emit(ReplFailed('Python worker failed to start: ${event.message}'));
      }).toJS
      ..postMessage(_InitMessage(
        type: 'init',
        wasmUrl: absoluteUrl(pythonWasmPath),
        stdlibUrl: absoluteUrl(pythonStdlibPath),
      ));
  }

  void _onMessage(_WorkerMessage message) {
    switch (message.type) {
      case 'ready':
        // The compile is done; hand over the channel and let it block. Nothing
        // may be posted to the worker after this.
        _worker?.postMessage(_StartMessage(type: 'start', channel: _channel!));
      case 'started':
        _emit(const ReplStarted());
      case 'output':
        for (final chunk in message.chunks?.toDart ?? const <_OutputChunk>[]) {
          _emit(ReplOutput(chunk.text, fromStderr: chunk.kind == 'stderr'));
        }
      case 'exited':
        _emit(ReplExited(message.code ?? 0));
      case 'failed':
        _emit(ReplFailed(message.message ?? 'The interpreter could not be started.'));
    }
  }

  void _emit(ReplEvent event) {
    if (_disposed || _events.isClosed) return;
    _events.add(event);
  }

  @override
  void write(String text) {
    final module = _module;
    final channel = _channel;
    if (module == null || channel == null) return;
    module.write(channel, text);
  }

  @override
  void endInput() {
    final module = _module;
    final channel = _channel;
    if (module == null || channel == null) return;
    module.close(channel);
  }

  @override
  void dispose() {
    _disposed = true;
    // Terminate rather than ask. The worker is parked inside a blocking read
    // and will never reach its event loop to be asked anything.
    _worker?.terminate();
    _worker = null;
    _channel = null;
    _module = null;
    _starting = null;
    unawaited(_events.close());
  }

}
