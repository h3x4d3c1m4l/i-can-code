import 'package:web/web.dart' as web;

/// Resolves a path against the *document*, so a worker or a module gets an
/// absolute URL.
///
/// Load-bearing: a relative URL fetched inside a worker resolves against the
/// worker script's location, not the page, so it would miss and the dev server
/// would answer the 404 with index.html, which the wasm compiler reports as
/// `expected magic word 00 61 73 6d, found 3c 21 44 4f` (`<!DO`).
///
/// Going through `baseURI` also survives a deploy under `--base-href`.
String absoluteUrl(String path) => Uri.parse(web.document.baseURI).resolve(path).toString();
