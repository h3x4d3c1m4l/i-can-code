import 'dart:convert';

import 'package:i_can_code/services/vm/vm_image.dart';
// Only a browser has the image to fetch. Everything else, the Dart VM a
// `flutter test` runs on included, falls through to the stub.
import 'package:i_can_code/services/vm/vm_manifest_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/vm/vm_manifest_web.dart'
    as impl;

/// The parts of the VM image's `manifest.json` that the about and licence
/// screens show. Reading it downloads nothing of the machine.
class VmManifest {

  /// The bundle's directory under [vmImagePath].
  final String imageId;

  /// What the saved machine's interpreter reported, such as "Python 3.14.8".
  final String? python;

  /// Tk's patch level, such as "8.6.17".
  final String? tk;

  /// The notices file inside the bundle, or null for a bundle built before it
  /// carried one.
  final String? notices;

  /// The size of [notices] in bytes, as the build wrote it.
  final int? noticesBytes;

  const VmManifest({required this.imageId, this.python, this.tk, this.notices, this.noticesBytes});

  /// Throws a [FormatException] on anything that is not a manifest, such as the
  /// `index.html` a dev server answers a missing file with.
  factory VmManifest.parse(String source) {
    final json = jsonDecode(source);
    if (json case {'imageId': final String imageId}) {
      final interpreter = json['interpreter'];
      final notices = json['notices'];
      return VmManifest(
        imageId: imageId,
        python: interpreter is Map ? interpreter['python'] as String? : null,
        tk: interpreter is Map ? interpreter['tk'] as String? : null,
        notices: notices is Map ? notices['file'] as String? : null,
        noticesBytes: notices is Map ? notices['bytes'] as int? : null,
      );
    }
    throw FormatException('Not a VM image manifest', source);
  }

  /// "Python 3.14.8 · Tk 8.6.17", or null when the manifest names no
  /// interpreter.
  String? get interpreterLabel => switch ((python, tk)) {
    (final python?, final tk?) => '$python · Tk $tk',
    (final python?, null) => python,
    _ => null,
  };

  /// Where [notices] is served, relative to the document.
  String? get noticesPath => notices == null ? null : '$vmImagePath$imageId/$notices';

}

/// The manifest of the image this build ships, or null when there is none to
/// read. Never throws.
Future<VmManifest?> loadVmManifest() => impl.loadVmManifest();

/// The image's `NOTICES.txt`: the licences of everything in it.
///
/// Throws when it cannot be read, or is not the size the manifest gives, as a
/// licence asset that is missing from the build does.
Future<String> loadVmNotices() => impl.loadVmNotices();
