import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';

import '../../bin/bundle_lessons.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('bundle_lessons_test'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String path, String text) => File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  test('every markdown file is bundled under the path the app looks for it at', () {
    write('python/contents.nl.md', '- [First](week-1/01-first.nl.md)\n');
    write('python/week-1/01-first.nl.md', 'first');
    write('python/unlisted.nl.md', 'unlisted');
    write('python/notes.txt', 'not markdown');

    final bundle = bundleLessons(root, lessonFiles(root));

    expect(bundle, {
      'assets/lessons/python/contents.nl.md': '- [First](week-1/01-first.nl.md)\n',
      'assets/lessons/python/unlisted.nl.md': 'unlisted',
      'assets/lessons/python/week-1/01-first.nl.md': 'first',
    });
    // Which of them is a lesson is the contents file's to say, at any depth.
    expect(Course.entriesFrom(bundle).single.paths, {'nl': 'assets/lessons/python/week-1/01-first.nl.md'});
  });

  test('an include is resolved while bundling, so the app never reads one', () {
    write('python/lesson.nl.md', '```python-assignment\n{{#include starters/a.py}}\n```\n');
    write('python/starters/a.py', 'print(...)\n');

    final read = <String>{};
    final bundle = bundleLessons(root, lessonFiles(root), read: read);

    expect(bundle, {'assets/lessons/python/lesson.nl.md': '```python-assignment\nprint(...)\n```\n'});
    // The depfile is written from this. Without the included file in it, a
    // change to that file alone would not bundle the course again.
    expect(read, {'${root.path}/python/lesson.nl.md', '${root.path}/python/starters/a.py'});
  });

  test('an include that names no file fails the bundle, rather than reaching a student', () {
    write('python/lesson.nl.md', '{{#include gone.py}}\n');

    expect(() => bundleLessons(root, lessonFiles(root)), throwsFormatException);
  });

  test('the keys start with the root the app matches them against', () {
    expect(keyPrefix, Course.root);
  });

  test('a checkout without a course bundles nothing, rather than failing the build', () {
    final missing = Directory('${root.path}/no-such-directory');

    expect(lessonFiles(missing), isEmpty);
    expect(bundleLessons(missing, lessonFiles(missing)), isEmpty);
  });
}
