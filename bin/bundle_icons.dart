// Compiles every icon the app names into the one asset `DuotoneIcon` loads.
//
// Flutter runs this as an asset transformer on `assets/icons.bin`, from the
// project root; see `pubspec.yaml`. By hand:
//
//   dart run i_can_code:bundle_icons --input=assets/icons.bin --output=icons.bin
//
// Of the app it imports only what is plain Dart, because the Dart VM a
// transformer runs on has no `dart:ui`.
import 'dart:io';
import 'dart:typed_data';

import 'package:i_can_code/services/icons/icon_bundle.dart';
import 'package:i_can_code/services/lessons/course_icon.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

/// The directory the SVG sources are read from, relative to the project root.
const String iconsDirectory = 'assets/icons';

/// The enum this bundles from. Named in the depfile, so adding an icon to it
/// runs the transformer again.
const String iconSet = 'lib/services/lessons/course_icon.dart';

Future<void> main(List<String> args) async {
  final output = _option(args, 'output');
  if (output == null) {
    stderr.writeln('usage: bundle_icons --input=<file> --output=<file>');
    exitCode = 64;
    return;
  }

  // `--input` is not read. A transformer takes one asset, and this one builds
  // its output from a directory, so the asset it is declared on is a placeholder.
  final Uint8List bundle;
  try {
    bundle = bundleIcons(Directory(iconsDirectory));
  } on FormatException catch (error) {
    stderr.writeln('bundle_icons: ${error.message}');
    exitCode = 65;
    return;
  }
  File(output).writeAsBytesSync(bundle);

  // Flutter reads `<output>.d` and reruns the transformer when a file listed in
  // it changes. Without it only a change to the placeholder would.
  final inputs = [iconSet, for (final icon in CourseIcon.values) _source(Directory(iconsDirectory), icon).path];
  File('$output.d').writeAsStringSync('${_escape(output)}: ${inputs.map(_escape).join(' ')}');
}

/// Every [CourseIcon], compiled from its SVG under [root].
///
/// Throws a [FormatException] for an icon whose file is missing or does not
/// compile: an icon that fails at runtime is an empty box and no error.
Uint8List bundleIcons(Directory root) {
  final icons = <String, Uint8List>{};
  for (final icon in CourseIcon.values) {
    final source = _source(root, icon);
    if (!source.existsSync()) throw FormatException('${icon.key} has no ${source.path}.');

    try {
      icons[icon.key] = encodeSvg(
        xml: source.readAsStringSync(),
        debugName: icon.key,
        // All three need Skia's path ops through FFI, which is not loaded here.
        // An icon has no mask or clip for the first two to work on, and the
        // third cuts a fill out from under the fill above it, which leaves a
        // seam at the antialiased edge once `DuotoneIcon` recolours the keys.
        enableMaskingOptimizer: false,
        enableClippingOptimizer: false,
        enableOverdrawOptimizer: false,
      );
    } on Object catch (error) {
      throw FormatException('${source.path} does not compile: $error');
    }
  }

  return IconBundle.encode(icons);
}

File _source(Directory root, CourseIcon icon) => File('${root.path}/${icon.key}.svg');

String? _option(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }

  return null;
}

/// A path as a Makefile-style depfile has it: a space escaped.
String _escape(String path) => path.replaceAll(' ', r'\ ');
