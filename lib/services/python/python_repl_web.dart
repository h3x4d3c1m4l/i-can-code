import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:i_can_code/services/python/python_build_web.dart';
import 'package:i_can_code/services/python/python_repl.dart';
import 'package:i_can_code/services/web/absolute_url_web.dart';
import 'package:web/web.dart' as web;

/// Copied verbatim from `web/python/` into the build output.
const String _workerPath = 'python/python_repl_worker.js';
const String _channelPath = 'python/stdin_channel.js';
const String _fileChannelPath = 'python/file_channel.js';

PythonRepl createPythonRepl({String? program, Map<String, Uint8List> files = const {}}) =>
    WebPythonRepl(program: program, files: files);

/// The module in `web/python/stdin_channel.js`, typed.
///
/// It is reached by `importModule` rather than rewritten in Dart because the
/// worker half has to be the same code, and because `Atomics` has no Dart
/// binding — the page's half is only `write`, `endOfInput` and two loads, so keeping
/// the protocol in one file is worth the interop.
extension type _StdinChannelModule(JSObject _) implements JSObject {

  external JSObject createChannel();

  external int write(JSObject channel, String text);

  external int endOfInput(JSObject channel);

  external bool isWaiting(JSObject channel);

}

/// The module in `web/python/file_channel.js`, typed.
extension type _FileChannelModule(JSObject _) implements JSObject {

  external JSObject createFileChannel();

  external int sendFiles(JSObject channel, JSObject stdinChannel, JSArray<_FileOp> ops);

}

/// A file to write, or with no [bytes] one to remove, by path relative to the
/// interpreter's root. Both ways: in the mailbox and `start`, and in `files`.
extension type _FileOp._(JSObject _) implements JSObject {

  external factory _FileOp({String path, JSUint8Array? bytes});

  external String get path;
  external JSUint8Array? get bytes;

}

extension type _StartMessage._(JSObject _) implements JSObject {

  external factory _StartMessage({
    String type,
    JSObject channel,
    JSObject fileChannel,
    JSArray<_FileOp> files,
    String? program,
  });

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
  external JSArray<_FileOp>? get changed;
  external JSArray<JSString>? get removed;

}

/// Runs one interactive CPython in a dedicated web worker.
///
/// The worker blocks for the whole session — it parks inside `fd_read` between
/// lines — so it can be sent exactly one message, `start`, and never another.
/// Input goes through the shared buffer instead, files through a second one
/// (`file_channel.js`), and stopping is termination.
class WebPythonRepl implements PythonRepl {

  final StreamController<ReplEvent> _events = StreamController<ReplEvent>.broadcast();

  /// Run instead of the prompt when given.
  final String? _program;

  /// The folder the interpreter starts with. Changed in place until `start`
  /// is posted, and never read again after.
  final Map<String, Uint8List> _files;

  web.Worker? _worker;
  _StdinChannelModule? _module;
  JSObject? _channel;
  _FileChannelModule? _fileModule;
  JSObject? _fileChannel;
  Future<void>? _starting;
  bool _startPosted = false;
  bool _disposed = false;

  /// What the page has said about a path since `start` and not yet sent, in the
  /// order it was said. Null is a removal.
  final Map<String, Uint8List?> _queued = {};

  /// Sent, and not yet taken by the worker. Nothing more is sent until it is.
  final Set<String> _inFlight = {};

  WebPythonRepl({this._program, Map<String, Uint8List> files = const {}}) : _files = Map.of(files);

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
      final fileModule = (await importModule(absoluteUrl(_fileChannelPath).toJS).toDart) as _FileChannelModule;
      _module = module;
      _channel = module.createChannel();
      _fileModule = fileModule;
      _fileChannel = fileModule.createFileChannel();
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
      }).toJS;

    final PythonBuild build;
    try {
      build = await loadPythonBuild();
    } on Object catch (error) {
      _emit(ReplFailed('$error'));
      return;
    }
    // Null once disposed, and a terminated worker would drop it anyway.
    _worker?.postMessage(build.initMessage);
  }

  void _onMessage(_WorkerMessage message) {
    switch (message.type) {
      case 'ready':
        // The worker holds the interpreter; hand over the channel and let it block. Nothing
        // may be posted to the worker after this.
        _worker?.postMessage(
          _StartMessage(
            type: 'start',
            channel: _channel!,
            fileChannel: _fileChannel!,
            files: [
              for (final MapEntry(:key, :value) in _files.entries) _FileOp(path: key, bytes: value.toJS),
            ].toJS,
            program: _program,
          ),
        );
        _startPosted = true;
        _sendFiles();
      case 'started':
        _emit(const ReplStarted());
      case 'output':
        for (final chunk in message.chunks?.toDart ?? const <_OutputChunk>[]) {
          _emit(ReplOutput(chunk.text, fromStderr: chunk.kind == 'stderr'));
        }
      case 'files':
        _onFiles(message);
      case 'filesTaken':
        _inFlight.clear();
        _sendFiles();
      case 'exited':
        _emit(ReplExited(message.code ?? 0));
      case 'failed':
        _emit(ReplFailed(message.message ?? 'The interpreter could not be started.'));
    }
  }

  /// Passes on what the program did, less what the page has said about since.
  /// A report about such a path was written before the worker heard what the
  /// page said, and what the page said is what the folder will hold.
  void _onFiles(_WorkerMessage message) {
    bool settled(String path) => !_queued.containsKey(path) && !_inFlight.contains(path);

    final changed = {
      for (final file in message.changed?.toDart ?? const <_FileOp>[])
        if (settled(file.path) && file.bytes != null) file.path: file.bytes!.toDart,
    };
    final removed = [
      for (final path in message.removed?.toDart ?? const <JSString>[])
        if (settled(path.toDart)) path.toDart,
    ];
    if (changed.isEmpty && removed.isEmpty) return;
    _emit(ReplFiles(changed: changed, removed: removed));
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
    module.endOfInput(channel);
  }

  @override
  void putFile(String path, Uint8List bytes) {
    if (bytes.length > PythonRepl.maxPutBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'Longer than ${PythonRepl.maxPutBytes}');
    }
    _say(path, bytes);
  }

  @override
  void removeFile(String path) => _say(path, null);

  void _say(String path, Uint8List? bytes) {
    if (_disposed) return;
    if (!_startPosted) {
      if (bytes == null) {
        _files.remove(path);
      } else {
        _files[path] = bytes;
      }
      return;
    }
    // To the end, so what was said last about anything is sent last.
    _queued
      ..remove(path)
      ..[path] = bytes;
    _sendFiles();
  }

  void _sendFiles() {
    final module = _fileModule;
    final fileChannel = _fileChannel;
    final channel = _channel;
    if (module == null || fileChannel == null || channel == null) return;
    if (!_startPosted || _inFlight.isNotEmpty || _queued.isEmpty) return;

    final entries = _queued.entries.toList();
    final taken = module.sendFiles(fileChannel, channel, [
      for (final MapEntry(:key, :value) in entries) _FileOp(path: key, bytes: value?.toJS),
    ].toJS);
    for (final MapEntry(:key) in entries.take(taken)) {
      _queued.remove(key);
      _inFlight.add(key);
    }
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
    _fileChannel = null;
    _fileModule = null;
    _starting = null;
    unawaited(_events.close());
  }

}
