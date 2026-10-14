import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const bool canDownloadFiles = true;

/// Clicks a hidden link to a `blob:` URL with a `download` name. A `blob:` URL
/// has the page's own origin, so cross-origin isolation does not stand in the way.
void downloadTextFile(String name, String text) {
  final blob = web.Blob(<web.BlobPart>[text.toJS].toJS, web.BlobPropertyBag(type: 'text/plain;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(link);
  link
    ..click()
    ..remove();
  // Not at once: a browser may start reading the URL after click() returns.
  Timer(const Duration(seconds: 10), () => web.URL.revokeObjectURL(url));
}
