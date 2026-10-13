// Imports nothing from Flutter: `bin/bundle_lessons.dart` runs on a Dart VM
// that has no `dart:ui`, and it resolves includes while it bundles.

/// `{{#include path}}`, alone on its line. The form is mdBook's:
/// https://rust-lang.github.io/mdBook/format/mdbook.html#including-files
final RegExp _directive = RegExp(r'^\s*\{\{#include\s+(.*?)\s*\}\}\s*$');

const String _opening = '{{#include';

/// An include that is neither a whole line nor escaped with a backslash.
final RegExp _stray = RegExp(r'(?<!\\)\{\{#include');

/// Returns [source] with every `{{#include path}}` line replaced by the text of
/// the file it names.
///
/// [path] is the file [source] came from. An include is relative to the file it
/// stands in, and [read] is asked for the result: forward slashes, no `.` or
/// `..`, in whatever namespace [path] itself is in. [read] MUST answer null for
/// a file that does not exist.
///
/// The replacement is textual and recursive, and a file's one trailing newline
/// is dropped so an include inside a fenced block adds no empty line to it.
/// `\{{#include` is written out without its backslash.
///
/// Throws a [FormatException] when an include names a file that does not
/// exist, climbs out of the namespace, includes itself through any number of
/// files, shares its line with other text, or asks for part of a file.
String resolveIncludes(String source, {required String path, required String? Function(String path) read}) =>
    _resolve(source, path, read, [path]);

String _resolve(String source, String path, String? Function(String path) read, List<String> chain) {
  if (!source.contains(_opening)) return source;

  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final resolved = <String>[];

  for (final line in lines) {
    final target = _directive.firstMatch(line)?.group(1);

    if (target == null) {
      if (_stray.hasMatch(line)) {
        throw FormatException('$path: an include has to stand alone on its line. Found: ${line.trim()}');
      }
      resolved.add(line.replaceAll('\\$_opening', _opening));
      continue;
    }

    final included = _locate(target, from: path);
    if (chain.contains(included)) {
      throw FormatException('$path includes $included, which is already being included: ${chain.join(' -> ')}.');
    }

    final text = read(included);
    if (text == null) throw FormatException('$path includes $target, which does not exist.');

    final body = _resolve(text.replaceAll('\r\n', '\n'), included, read, [...chain, included]);
    resolved.add(body.endsWith('\n') ? body.substring(0, body.length - 1) : body);
  }

  return resolved.join('\n');
}

/// Where [target] is, for an include written in the file at [from].
String _locate(String target, {required String from}) {
  if (target.isEmpty) throw FormatException('$from has an include that names no file.');
  // mdBook's `file:2:10` and `file:anchor`. Kept free so they can be added
  // without changing what a path means.
  if (target.contains(':')) {
    throw FormatException('$from includes $target: only whole files can be included, not a part of one.');
  }
  if (target.startsWith('/')) {
    throw FormatException('$from includes $target: a path is relative to the file the include is in.');
  }

  final segments = from.split('/')..removeLast();
  for (final segment in target.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment != '..') {
      segments.add(segment);
    } else if (segments.isEmpty) {
      throw FormatException('$from includes $target, which is outside the lessons.');
    } else {
      segments.removeLast();
    }
  }

  return segments.join('/');
}
