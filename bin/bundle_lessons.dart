// Bundles every lesson file into the one JSON asset the app loads at startup.
//
// Flutter runs this as an asset transformer on `assets/course.json`, from the
// project root; see `pubspec.yaml`. By hand:
//
//   dart run i_can_code:bundle_lessons --input=assets/course.json --output=course.json
//
// It imports nothing from the app: `course.dart` reaches Flutter, and the Dart
// VM a transformer runs on has no `dart:ui`.
import 'dart:convert';
import 'dart:io';

/// The directory the lesson files are read from, relative to the project root.
const String lessonsDirectory = 'assets/lessons';

/// What every key of the bundle starts with. MUST stay in step with
/// `Course.root`, which is what the app matches a key against.
const String keyPrefix = 'assets/lessons/';

Future<void> main(List<String> args) async {
  final output = _option(args, 'output');
  if (output == null) {
    stderr.writeln('usage: bundle_lessons --input=<file> --output=<file>');
    exitCode = 64;
    return;
  }

  // `--input` is not read. A transformer takes one asset, and this one builds
  // its output from a directory, so the asset it is declared on is a placeholder.
  final root = Directory(lessonsDirectory);
  final files = lessonFiles(root);
  File(output).writeAsStringSync(jsonEncode(bundleLessons(root, files)));

  // Flutter reads `<output>.d` and reruns the transformer when a file listed in
  // it changes. Without it only a change to the placeholder would.
  File('$output.d').writeAsStringSync('${_escape(output)}: ${files.map((file) => _escape(file.path)).join(' ')}');
}

/// Every markdown file under [root], at any depth, in path order. Empty when
/// [root] does not exist, which is a checkout without a course.
///
/// Which of them are lessons is the app's decision (`Course.entriesFrom`), so a
/// naming rule lives in one place.
List<File> lessonFiles(Directory root) {
  if (!root.existsSync()) return const [];

  return root.listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.md')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// The bundle: each of [files] by the asset path it had when lessons were
/// assets of their own, `assets/lessons/<subject>/…`, whatever [root] is.
Map<String, String> bundleLessons(Directory root, List<File> files) => {
  for (final file in files)
    keyPrefix + file.path.substring(root.path.length + 1).replaceAll(r'\', '/'): file.readAsStringSync(),
};

String? _option(List<String> args, String name) {
  final prefix = '--$name=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }

  return null;
}

/// A depfile separates paths with a space, so one inside a path is escaped.
String _escape(String path) => path.replaceAll(' ', r'\ ');
