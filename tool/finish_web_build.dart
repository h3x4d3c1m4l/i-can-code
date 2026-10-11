// Finishes what `flutter build web` leaves in `build/web`.
//
//   dart run tool/finish_web_build.dart build/web
//
// `just build` and both workflows run it straight after the build. `flutter run`
// serves a build this never sees, so the page keeps its spinner there.
//
// It does what the build has no switch for: it takes a font nothing draws with
// out of the font manifest, and writes the sizes of everything a cold start
// downloads into `index.html`, which is what the progress ring measures against.
import 'dart:convert';
import 'dart:io';

/// What `web/index.html` holds where the size table goes.
const String sizesPlaceholder = '/*STARTUP_SIZES*/null';

/// The family forui bundles and this app never draws with: `buildAppTheme()`
/// replaces both of forui's typefaces. The web engine downloads every font in
/// the manifest before the first frame, used or not.
const String unusedFontFamily = 'packages/forui/Inter';

/// Where the build puts the course bundle. MUST stay `assets/` followed by
/// `Course.bundleAsset`; this tool cannot import it, because `course.dart`
/// reaches Flutter and the Dart VM has no `dart:ui`.
const String courseBundlePath = 'assets/assets/course.json';

/// The build is not what this tool was written for, and finishing it anyway
/// would ship something that quietly does less than it says.
class BuildCheckFailure implements Exception {

  final String message;

  const BuildCheckFailure(this.message);

  @override
  String toString() => message;

}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/finish_web_build.dart <build/web>');
    exitCode = 64;
    return;
  }

  final web = Directory(args.single);
  try {
    checkAssumptions(web);
    final removed = stripUnusedFont(web);
    final sizes = startupSizes(web);
    writeStartupSizes(web, sizes);

    stdout
      ..writeln('Removed ${removed.length} unused font files ($unusedFontFamily).')
      ..writeln('Wrote the sizes of ${sizes.files.length} startup files into index.html.');
  } on BuildCheckFailure catch (failure) {
    stderr.writeln('ERROR: ${failure.message}');
    exitCode = 1;
  }
}

/// Fails unless [web] is a build the page's progress ring can measure.
///
/// Throws [BuildCheckFailure].
void checkAssumptions(Directory web) {
  final index = _existing(web, 'index.html').readAsStringSync();
  if (!index.contains('"useLocalCanvasKit":true')) {
    throw const BuildCheckFailure(
      'This build loads CanvasKit from www.gstatic.com. Build with `--no-web-resources-cdn`.',
    );
  }

  // The ring counts bytes in a wrapper around `window.fetch`. An engine that
  // downloads some other way leaves it counting nothing.
  if (!_existing(web, 'main.dart.js').readAsStringSync().contains('.window.fetch(')) {
    throw const BuildCheckFailure(
      'main.dart.js no longer calls window.fetch, which is where web/index.html counts downloaded bytes. '
      'Read how the engine fetches assets now and update the wrapper there.',
    );
  }
}

/// Takes [unusedFontFamily] out of the font manifest and deletes its files.
/// Returns the paths it deleted, relative to [web].
///
/// Throws [BuildCheckFailure] when the family is not there: forui changed what
/// it bundles, and whether the app draws with it has to be looked at again.
List<String> stripUnusedFont(Directory web) {
  final file = _existing(web, 'assets/FontManifest.json');
  final manifest = (jsonDecode(file.readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>();

  final unused = manifest.where((family) => family['family'] == unusedFontFamily).toList();
  if (unused.isEmpty) {
    throw const BuildCheckFailure(
      'The font manifest has no "$unusedFontFamily". Either this build was finished already, or forui '
      'changed the fonts it bundles: check what it bundles now and whether the app draws with it.',
    );
  }

  final removed = [for (final family in unused) ..._assetsOf(family).map((asset) => 'assets/$asset')];
  for (final path in removed) {
    _existing(web, path).deleteSync();
  }
  file.writeAsStringSync(jsonEncode(manifest.where((family) => family['family'] != unusedFontFamily).toList()));

  return removed;
}

/// The size of each file a cold start downloads: `[bytes, bytes gzipped]` by
/// path relative to [web].
///
/// Only one of [canvasKit] is downloaded, and which one is the browser's
/// choice, so they are kept apart from [files].
typedef StartupSizes = ({Map<String, List<int>> files, Map<String, List<int>> canvasKit});

/// Measures everything the page fetches before the first screen.
///
/// Throws [BuildCheckFailure] when a file the font manifest names is missing.
StartupSizes startupSizes(Directory web) {
  final manifest = (jsonDecode(_existing(web, 'assets/FontManifest.json').readAsStringSync()) as List<dynamic>)
      .cast<Map<String, dynamic>>();

  // A set: one file may be bundled under two families, and is fetched once per
  // family but only weighs once.
  final paths = <String>{
    'main.dart.js',
    'assets/FontManifest.json',
    for (final family in manifest) ..._assetsOf(family).map((asset) => 'assets/$asset'),
    courseBundlePath,
  };

  final canvasKit = Directory('${web.path}/canvaskit');
  final variants = !canvasKit.existsSync()
      ? const <String>[]
      : (canvasKit
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => file.path.substring(web.path.length + 1).replaceAll(r'\', '/'))
            .where((path) => path.endsWith('/canvaskit.wasm'))
            .toList()
          ..sort());
  if (variants.isEmpty) throw const BuildCheckFailure('The build has no canvaskit.wasm under canvaskit/.');

  return (
    files: {for (final path in paths) path: _sizeOf(_existing(web, path))},
    canvasKit: {for (final path in variants) path: _sizeOf(_existing(web, path))},
  );
}

/// Puts [sizes] where `index.html` holds [sizesPlaceholder].
///
/// Throws [BuildCheckFailure] when the placeholder is not there exactly once.
void writeStartupSizes(Directory web, StartupSizes sizes) {
  final file = _existing(web, 'index.html');
  final index = file.readAsStringSync();
  if (sizesPlaceholder.allMatches(index).length != 1) {
    throw const BuildCheckFailure(
      'index.html does not hold `$sizesPlaceholder` exactly once. Either this build was finished '
      'already, or web/index.html lost the placeholder its progress ring reads.',
    );
  }

  file.writeAsStringSync(
    index.replaceFirst(sizesPlaceholder, jsonEncode({'files': sizes.files, 'canvasKit': sizes.canvasKit})),
  );
}

Iterable<String> _assetsOf(Map<String, dynamic> family) =>
    (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>().map((font) => font['asset'] as String);

File _existing(Directory web, String path) {
  final file = File('${web.path}/$path');
  if (!file.existsSync()) throw BuildCheckFailure('${web.path} has no $path. Is it a finished `flutter build web`?');

  return file;
}

/// GitHub Pages serves these gzipped, so the gzipped size is what a download
/// costs, and the plain size is what the page can count as it arrives.
List<int> _sizeOf(File file) {
  final bytes = file.readAsBytesSync();

  return [bytes.length, gzip.encode(bytes).length];
}
