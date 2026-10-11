// Serves a finished web build on localhost, the way the app needs to be served.
//
//   dart run tool/serve_web_build.dart build/web [port]
//
// It sends the two cross-origin isolation headers itself, as every `flutter run`
// configuration does. A plain static server leaves that to the service worker in
// web/, and a hard reload skips a service worker, as does a reload with DevTools'
// "Disable cache" on some of the time. The page then comes up without
// `SharedArrayBuffer` and the console says it cannot run.
//
// Every response is `no-cache` with an ETag, so a rebuild is picked up on the
// next load and an unchanged file costs a 304 and no download.
import 'dart:async';
import 'dart:io';

const Map<String, String> _contentTypes = {
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript; charset=utf-8',
  'mjs': 'text/javascript; charset=utf-8',
  'json': 'application/json; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'txt': 'text/plain; charset=utf-8',
  'svg': 'image/svg+xml',
  'png': 'image/png',
  'ico': 'image/x-icon',
  // `WebAssembly.compileStreaming` refuses any other type.
  'wasm': 'application/wasm',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'zip': 'application/zip',
};

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('usage: dart run tool/serve_web_build.dart <build/web> [port]');
    exitCode = 64;
    return;
  }

  final root = Directory(args.first).absolute;
  if (!File('${root.path}/index.html').existsSync()) {
    stderr.writeln('ERROR: ${args.first} has no index.html. Run `just build` first.');
    exitCode = 66;
    return;
  }

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, args.length == 2 ? int.parse(args[1]) : 8080);
  stdout.writeln('Serving ${args.first} on http://localhost:${server.port} (Ctrl-C stops it).');

  await for (final request in server) {
    // Not awaited: a page asks for many files at once, and a slow one must not
    // hold up the rest. A failure is a browser that stopped listening, on a
    // reload for one, and there is nobody left to tell.
    unawaited(_answer(request, root).catchError((Object _) {}));
  }
}

Future<void> _answer(HttpRequest request, Directory root) async {
  final response = request.response;
  response.headers
    ..set('Cross-Origin-Opener-Policy', 'same-origin')
    ..set('Cross-Origin-Embedder-Policy', 'require-corp')
    ..set(HttpHeaders.cacheControlHeader, 'no-cache');

  // Segments, not the raw path, so `..` cannot climb out of the build.
  final segments = request.uri.pathSegments.where((segment) => segment.isNotEmpty && segment != '..').toList();
  var file = File([root.path, ...segments].join(Platform.pathSeparator));
  if (FileSystemEntity.isDirectorySync(file.path)) file = File('${file.path}/index.html');

  if (!file.existsSync()) {
    response.statusCode = HttpStatus.notFound;
    await response.close();
    return;
  }

  final stat = file.statSync();
  final etag = '"${stat.size}-${stat.modified.millisecondsSinceEpoch}"';
  response.headers
    ..set(HttpHeaders.etagHeader, etag)
    ..set(
      HttpHeaders.contentTypeHeader,
      _contentTypes[file.path.split('.').last.toLowerCase()] ?? 'application/octet-stream',
    );

  if (request.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
    response.statusCode = HttpStatus.notModified;
    await response.close();
    return;
  }

  response.contentLength = stat.size;
  if (request.method != 'HEAD') await response.addStream(file.openRead());
  await response.close();
}
