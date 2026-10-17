import 'dart:convert';
import 'dart:js_interop';

import 'package:i_can_code/services/vm/vm_image.dart';
import 'package:i_can_code/services/vm/vm_manifest.dart';
import 'package:web/web.dart' as web;

/// Relative, so it resolves against the document and survives a deploy under
/// `--base-href`.
const String _manifestPath = '${vmImagePath}manifest.json';

Future<VmManifest?> loadVmManifest() async {
  try {
    return VmManifest.parse(await _fetchText(_manifestPath));
  } on Object {
    return null;
  }
}

Future<String> loadVmNotices() async {
  final manifest = VmManifest.parse(await _fetchText(_manifestPath));
  final path = manifest.noticesPath;
  if (path == null) throw StateError('The VM image ${manifest.imageId} names no notices.');

  final text = await _fetchText(path);
  // The dev server answers a missing file with index.html and a 200, which is
  // not the size the build wrote down.
  final bytes = utf8.encode(text).length;
  if (manifest.noticesBytes case final expected? when expected != bytes) {
    throw StateError('$path is $bytes bytes, and the manifest says $expected.');
  }
  return text;
}

Future<String> _fetchText(String path) async {
  final response = await web.window.fetch(path.toJS).toDart;
  if (!response.ok) throw StateError('${response.status} fetching $path');
  return (await response.text().toDart).toDart;
}
