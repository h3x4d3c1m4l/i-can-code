// Imports nothing from Flutter, for the reason `includes.dart` gives.

/// A group as one contents file states it: the id every locale shares, the
/// heading in that file's own language, and the feature toggle that has to be
/// on for the group to be shown, if any.
typedef ContentsGroup = ({String id, String title, String? feature});

/// One lesson a contents file lists.
class ContentsItem {

  /// The link's text. What the contents file calls the lesson, which
  /// `test/content/lessons_test.dart` holds to the lesson's own title.
  final String title;

  /// The lesson's file, relative to the contents file. Forward slashes, and no
  /// `.` or `..`.
  final String path;

  /// The heading the lesson is listed under, or null for a lesson under none.
  final ContentsGroup? group;

  const ContentsItem({required this.title, required this.path, this.group});

}

/// A subject's lessons, in order and under their groups, as one
/// `contents.<locale>.md` lists them. See `docs/lesson-format.md`.
///
/// The form is mdBook's `SUMMARY.md`, kept to what a course needs:
/// https://rust-lang.github.io/mdBook/format/summary.html
class SubjectContents {

  /// `contents.<locale>.md`.
  static final RegExp fileName = RegExp(r'^contents\.([a-z]{2})\.md$');

  static final RegExp _heading = RegExp(r'^(#+)\s+(.*)$');

  /// A heading's text and the `{#id}` it ends in, which MAY name a feature
  /// toggle beside the id: `{#week-5 feature=files}`. mdBook's heading
  /// attributes: https://rust-lang.github.io/mdBook/format/markdown.html#heading-attributes
  static final RegExp _groupId = RegExp(
    r'^(.*?)\s*\{\s*#([a-z0-9-]+)(?:\s+feature=([a-z0-9-]+))?\s*\}$',
  );

  static final RegExp _separator = RegExp(r'^-{3,}$');
  static final RegExp _item = RegExp(r'^[-*]\s+\[(.+)\]\(([^()\s]*)\)$');
  static final RegExp _listMarker = RegExp(r'^\s+[-*]\s');

  /// In the order the file lists them, which is the order of the course.
  final List<ContentsItem> items;

  const SubjectContents({required this.items});

  /// Parses [source], one contents file.
  ///
  /// Strict, as mdBook's is: a line that is not a group heading, a lesson or a
  /// `---` throws rather than being skipped, so a typing mistake cannot quietly
  /// drop a lesson from the course.
  ///
  /// Throws a [FormatException] naming the line.
  static SubjectContents parse(String source) {
    final items = <ContentsItem>[];
    final groups = <String>{};
    final paths = <String>{};
    ContentsGroup? group;

    final lines = source.replaceAll('\r\n', '\n').split('\n');
    for (final (index, raw) in lines.indexed) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;

      Never fail(String what) => throw FormatException('Line ${index + 1}: $what');

      if (_listMarker.hasMatch(line)) fail('a lesson cannot be nested under another.');

      if (_separator.hasMatch(line)) {
        group = null;
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        if (heading.group(1) != '#') fail('only a `#` heading starts a group.');

        final named = _groupId.firstMatch(heading.group(2)!);
        if (named == null || named.group(1)!.isEmpty) {
          fail('a group needs a title and an id, and may name a feature: `# Week 1 {#week-1 feature=files}`.');
        }
        final id = named.group(2)!;
        if (!groups.add(id)) fail('the group id "$id" is used twice.');

        group = (id: id, title: named.group(1)!, feature: named.group(3));
        continue;
      }

      final item = _item.firstMatch(line);
      if (item == null) fail('expected a group heading, a lesson link or `---`. Found: $line');

      final path = _normalise(item.group(2)!, fail);
      if (!paths.add(path)) fail('$path is listed twice.');

      items.add(ContentsItem(title: item.group(1)!.trim(), path: path, group: group));
    }

    return SubjectContents(items: items);
  }

  /// [path] without `.` segments. Refuses one that could leave the subject's
  /// directory.
  static String _normalise(String path, Never Function(String what) fail) {
    if (path.isEmpty) fail('a lesson needs a file to link to.');
    if (path.startsWith('/') || path.contains(':')) fail('$path has to be relative to the contents file.');

    final segments = path.split('/').where((segment) => segment.isNotEmpty && segment != '.').toList();
    if (segments.contains('..')) fail('$path leaves the directory of its subject.');

    return segments.join('/');
  }

}
