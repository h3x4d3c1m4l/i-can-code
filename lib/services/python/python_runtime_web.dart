import 'dart:async';
import 'dart:js_interop';

import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:web/web.dart' as web;

/// Where Flutter serves the declared assets from. The doubled `assets/` is not a
/// typo: the build copies `assets/python/...` under its own `assets/` root.
const String _wasmPath = 'assets/assets/python/python.wasm';
const String _stdlibPath = 'assets/assets/python/python314.zip';

/// Copied verbatim from `web/python/` into the build output.
const String _workerPath = 'python/python_worker.js';

/// Resolves a path against the *document*, so the worker gets absolute URLs.
///
/// Load-bearing: a relative URL fetched inside a worker resolves against the
/// worker script's location, not the page, so it would miss and the dev server
/// would answer the 404 with index.html — which the wasm compiler reports as
/// `expected magic word 00 61 73 6d, found 3c 21 44 4f` (`<!DO`).
///
/// Going through `baseURI` also survives a deploy under `--base-href`.
String _absoluteUrl(String path) => Uri.parse(web.document.baseURI).resolve(path).toString();

PythonRuntime createPythonRuntime() => WebPythonRuntime();

/// Runs CPython in a web worker.
///
/// The worker exists for the stop button, not for UI smoothness: a program that
/// never returns cannot be asked to stop, so [cancel] terminates the whole
/// worker from outside. The worker is therefore disposable and respawned on
/// demand.
class WebPythonRuntime implements PythonRuntime {

  web.Worker? _worker;
  Future<void>? _readying;
  Completer<PythonResult>? _pending;
  int _nextId = 0;
  String? _version;

  @override
  bool get isSupported => true;

  /// Reported by the worker with its `ready`, and kept across a [cancel]: the
  /// build being restarted is the same one that named itself.
  @override
  String? get version => _version;

  @override
  Future<void> ready() => _readying ??= _start();

  Future<void> _start() {
    final completer = Completer<void>();
    final worker = web.Worker(
      _absoluteUrl(_workerPath).toJS,
      web.WorkerOptions(type: 'module'),
    );
    _worker = worker;

    worker
      ..onmessage = (web.MessageEvent event) {
        final data = event.data.dartify()! as Map<Object?, Object?>;
        switch (data['type']) {
          case 'ready':
            // Null when the probe failed. The interpreter is still usable, so
            // this MUST NOT keep the worker from being ready.
            _version = data['version'] as String?;
            if (!completer.isCompleted) completer.complete();
          case 'result':
            _complete(PythonResult(
              stdout: data['stdout']! as String,
              stderr: data['stderr']! as String,
              exitCode: (data['exitCode']! as num).toInt(),
              truncated: data['truncated']! as bool,
              duration: Duration(milliseconds: (data['durationMs']! as num).toInt()),
            ));
          case 'failed':
            final message = data['message']! as String;
            if (!completer.isCompleted) completer.completeError(StateError(message));
            _complete(PythonResult.failure(message));
        }
      }.toJS
      ..onerror = (web.ErrorEvent event) {
        final error = StateError('Python worker failed to start: ${event.message}');
        if (!completer.isCompleted) completer.completeError(error);
        _complete(PythonResult.failure(error.message));
      }.toJS
      ..postMessage({
        'type': 'init',
        'wasmUrl': _absoluteUrl(_wasmPath),
        'stdlibUrl': _absoluteUrl(_stdlibPath),
      }.jsify());

    return completer.future;
  }

  void _complete(PythonResult result) {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(result);
  }

  @override
  Future<PythonResult> run(String code, {String stdin = ''}) async {
    // A run still in flight is ended, never refused. Refusing is what left a
    // student who walked away from a `sleep(3000)` with a runtime that answered
    // "a program is already running" to every attempt afterwards, and nothing
    // they could press to clear it. The worker is disposable by design, so
    // superseding one run with the next costs a restart and nothing else.
    if (_pending != null) await cancel();

    try {
      await ready();
    } on Object catch (error) {
      return PythonResult.failure('$error');
    }

    final completer = Completer<PythonResult>();
    _pending = completer;
    _worker!.postMessage({
      'type': 'run',
      'id': _nextId++,
      'code': code,
      'stdin': stdin,
    }.jsify());
    return completer.future;
  }

  @override
  Future<void> cancel() async {
    if (_pending == null) return;
    // Terminate rather than ask: the program may be in a loop that never
    // yields.
    _worker?.terminate();
    _worker = null;
    _readying = null;
    _complete(const PythonResult(stdout: '', stderr: 'Stopped.', exitCode: 130));
    // Warm the next one now, so the following Run does not pay for the restart.
    unawaited(ready().catchError((_) {}));
  }

  @override
  void dispose() {
    _worker?.terminate();
    _worker = null;
    _readying = null;
    _pending = null;
  }

}
