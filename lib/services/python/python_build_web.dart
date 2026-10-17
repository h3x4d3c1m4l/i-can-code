import 'dart:js_interop';
import 'dart:math';

import 'package:i_can_code/services/python/python_assets_web.dart';
import 'package:i_can_code/services/web/absolute_url_web.dart';
import 'package:web/web.dart' as web;

extension type _InitMessage._(JSObject _) implements JSObject {

  external factory _InitMessage({String type, web.Module module, JSArrayBuffer stdlib});

}

/// CPython compiled for this page, with its standard library, as every worker
/// in `web/python/` is started with.
///
/// A worker is disposable: Stop terminates the lesson's, and a restart replaces
/// the console's. Compiling in the worker paid for the 7 MB module again each
/// time, and once more for the console. A `WebAssembly.Module` can be posted to
/// a worker, so the page compiles it once and hands it to each.
class PythonBuild {

  final web.Module module;

  /// The zip the interpreter imports from. Posting it copies it, so each worker
  /// gets its own and none can change this one.
  final JSArrayBuffer stdlib;

  const PythonBuild(this.module, this.stdlib);

  /// The `init` message both workers expect.
  JSObject get initMessage => _InitMessage(type: 'init', module: module, stdlib: stdlib);

}

Future<PythonBuild>? _loading;

/// The build for this page, fetched and compiled by the first caller.
///
/// A failure is not kept, so a later caller tries again.
Future<PythonBuild> loadPythonBuild() => _loading ??= _load();

Future<PythonBuild> _load() async {
  try {
    // Not compileStreaming: that refuses anything not served as
    // `application/wasm`, and Flutter's dev server sends a generic type for
    // assets. It would work in a release build and fail from the IDE.
    final wasmUrl = absoluteUrl(pythonWasmPath);
    final [wasm, stdlib] = await Future.wait([_fetch(wasmUrl), _fetch(absoluteUrl(pythonStdlibPath))]);
    _assertWasm(wasm, wasmUrl);
    // Asynchronous, so the engine compiles off the main thread.
    final module = await web.WebAssembly.compile(wasm).toDart;
    return PythonBuild(module, stdlib);
  } on Object {
    _loading = null;
    rethrow;
  }
}

Future<JSArrayBuffer> _fetch(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) throw StateError('${response.status} fetching $url');
  return response.arrayBuffer().toDart;
}

/// Names the mistake behind the least helpful error here.
///
/// A single-page server answers a missing asset with `index.html` and a 200, and
/// the compiler then reports "expected magic word 00 61 73 6d, found 3c 21 44 4f",
/// which is `<!DO`.
void _assertWasm(JSArrayBuffer buffer, String url) {
  final bytes = buffer.toDart;
  final header = bytes.asUint8List(0, min(4, bytes.lengthInBytes));
  if (header.length == 4 && header[0] == 0x00 && header[1] == 0x61 && header[2] == 0x73 && header[3] == 0x6d) return;

  throw StateError(
    header.isNotEmpty && header[0] == 0x3c
        ? '$url returned HTML, not WebAssembly: the asset URL is wrong and the server answered with index.html.'
        : '$url is not a WebAssembly module.',
  );
}
