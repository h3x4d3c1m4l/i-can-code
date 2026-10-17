import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/subject_contents.dart';

Matcher _refuses(String what) => throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(what)));

void main() {
  group('SubjectContents.parse', () {
    test('reads lessons in order, each under the heading above it', () {
      final contents = SubjectContents.parse('''
- [Introductie](00-introductie.nl.md)

# Week 1 · De basis {#week-1}

- [Uitvoer](week-1/00-uitvoer.nl.md)
* [Waarden bewaren](week-1/01-waarden-bewaren.nl.md)

# Projecten · micro:bit {#microbit}

- [Dobbelsteen](microbit/00-dobbelsteen.nl.md)
''');

      expect(contents.items.map((item) => item.title), ['Introductie', 'Uitvoer', 'Waarden bewaren', 'Dobbelsteen']);
      expect(contents.items.map((item) => item.path), [
        '00-introductie.nl.md',
        'week-1/00-uitvoer.nl.md',
        'week-1/01-waarden-bewaren.nl.md',
        'microbit/00-dobbelsteen.nl.md',
      ]);
      expect(contents.items.map((item) => item.group?.id), [null, 'week-1', 'week-1', 'microbit']);
      expect(contents.items[1].group!.title, 'Week 1 · De basis');
    });

    test('a `---` ends the group, so what follows stands under no heading', () {
      final contents = SubjectContents.parse('''
# Week 1 {#week-1}
- [A](a.md)
---
- [B](b.md)
# Week 2 {#week-2}
- [C](c.md)
''');

      expect(contents.items.map((item) => item.group?.id), ['week-1', null, 'week-2']);
    });

    test('an id may be written with room around it, as mdBook allows', () {
      final contents = SubjectContents.parse('# Week 1 { #week-1 }\n- [A](a.md)\n');

      expect(contents.items.single.group, (id: 'week-1', title: 'Week 1', feature: null));
    });

    test('a group may name a feature toggle beside its id', () {
      final contents = SubjectContents.parse('# Week 5 {#week-5 feature=files}\n- [A](a.md)\n# Week 6 {#week-6}\n- [B](b.md)\n');

      expect(contents.items.map((item) => item.group?.feature), ['files', null]);
      expect(contents.items.first.group?.id, 'week-5');
    });

    test('a feature spelled unlike a group id is refused', () {
      expect(
        () => SubjectContents.parse('# Week 5 {#week-5 feature=Files}\n- [A](a.md)\n'),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Line 1'))),
      );
    });

    test('a title may hold brackets of its own', () {
      final contents = SubjectContents.parse('- [Lijsten: [1, 2, 3]](lijsten.md)\n');

      expect(contents.items.single.title, 'Lijsten: [1, 2, 3]');
    });

    test('a path is written without its `.` segments', () {
      expect(SubjectContents.parse('- [A](./week-1/./a.md)\n').items.single.path, 'week-1/a.md');
    });

    test('an empty file lists nothing', () {
      expect(SubjectContents.parse('\n\n').items, isEmpty);
    });

    test('a group without an id is refused', () {
      // An id made from the heading's words would change with them, and with
      // the language.
      expect(() => SubjectContents.parse('# Week 1\n'), _refuses('needs a title and an id'));
      expect(() => SubjectContents.parse('# {#week-1}\n'), _refuses('needs a title and an id'));
    });

    test('a group id used twice is refused', () {
      expect(
        () => SubjectContents.parse('# Een {#week}\n- [A](a.md)\n# Twee {#week}\n- [B](b.md)\n'),
        _refuses('"week" is used twice'),
      );
    });

    test('a lesson listed twice is refused', () {
      expect(() => SubjectContents.parse('- [A](a.md)\n- [Nog eens](./a.md)\n'), _refuses('a.md is listed twice'));
    });

    test('a deeper heading, a nested lesson and loose text are refused, each by its line', () {
      expect(() => SubjectContents.parse('# W {#w}\n## Dieper {#d}\n'), _refuses('Line 2: only a `#` heading'));
      expect(() => SubjectContents.parse('- [A](a.md)\n  - [B](b.md)\n'), _refuses('Line 2: a lesson cannot be'));
      expect(() => SubjectContents.parse('\n\nZomaar een zin.\n'), _refuses('Line 3: expected a group heading'));
    });

    test('a lesson with no file is refused, where mdBook would draw a draft', () {
      expect(() => SubjectContents.parse('- [Komt nog]()\n'), _refuses('needs a file'));
    });

    test('a path that could leave the subject is refused', () {
      expect(() => SubjectContents.parse('- [A](../javascript/a.md)\n'), _refuses('leaves the directory'));
      expect(() => SubjectContents.parse('- [A](/a.md)\n'), _refuses('relative to the contents file'));
      expect(() => SubjectContents.parse('- [A](https://x.nl/a.md)\n'), _refuses('relative to the contents file'));
    });

    test('its own file name carries a locale', () {
      expect(SubjectContents.fileName.firstMatch('contents.nl.md')!.group(1), 'nl');
      expect(SubjectContents.fileName.hasMatch('contents.md'), isFalse);
    });
  });
}
