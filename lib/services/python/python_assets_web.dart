import 'package:web/web.dart' as web;

/// Where Flutter serves the declared assets from. The doubled `assets/` is not a
/// typo: the build copies `assets/python/...` under its own `assets/` root.
const String pythonWasmPath = 'assets/assets/python/python.wasm';
const String pythonStdlibPath = 'assets/assets/python/python314.zip';

/// Resolves a path against the *document*, so a worker gets absolute URLs.
///
/// Load-bearing: a relative URL fetched inside a worker resolves against the
/// worker script's location, not the page, so it would miss and the dev server
/// would answer the 404 with index.html — which the wasm compiler reports as
/// `expected magic word 00 61 73 6d, found 3c 21 44 4f` (`<!DO`).
///
/// Going through `baseURI` also survives a deploy under `--base-href`.
String absoluteUrl(String path) => Uri.parse(web.document.baseURI).resolve(path).toString();
