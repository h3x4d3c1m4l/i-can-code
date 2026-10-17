import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Relative, so it resolves against the document like `RustLib.init` does and
/// survives a deploy under `--base-href`.
const String _path = 'pkg/rustc-version.txt';

Future<String?> loadRustcVersion() async {
  try {
    final response = await web.window.fetch(_path.toJS).toDart;
    if (!response.ok) return null;

    final text = (await response.text().toDart).toDart.trim();
    // The dev server answers a missing file with index.html and a 200.
    return text.startsWith('rustc ') ? text : null;
  } on Object {
    return null;
  }
}
