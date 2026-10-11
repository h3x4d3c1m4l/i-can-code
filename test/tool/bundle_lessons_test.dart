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
    write('python/02-second.nl.md', 'second');
    write('python/01-first.nl.md', 'first');
    write('python/microbit/01-dice.nl.md', 'dice');
    write('python/notes.txt', 'not markdown');

    final bundle = bundleLessons(root, lessonFiles(root));

    expect(bundle, {
      'assets/lessons/python/01-first.nl.md': 'first',
      'assets/lessons/python/02-second.nl.md': 'second',
      'assets/lessons/python/microbit/01-dice.nl.md': 'dice',
    });
    // A track is a folder deeper, and the app has to find it there too.
    expect(Course.entriesFrom(bundle.keys).map((e) => e.track), [null, null, 'microbit']);
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
