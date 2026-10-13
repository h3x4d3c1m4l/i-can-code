import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/includes.dart';
import 'package:i_can_code/services/lessons/lesson.dart';

Matcher _refuses(String what) => throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(what)));

/// Resolves [source] as `python/les.md`, with [files] as everything else there is.
String _resolve(String source, [Map<String, String> files = const {}]) =>
    resolveIncludes(source, path: 'python/les.md', read: (path) => files[path]);

void main() {
  group('resolveIncludes', () {
    test('puts a file where the line that names it stood', () {
      final resolved = _resolve(
        'before\n{{#include checks/a.py}}\nafter\n',
        {'python/checks/a.py': 'print(1)\nprint(2)\n'},
      );

      expect(resolved, 'before\nprint(1)\nprint(2)\nafter\n');
    });

    test('adds no empty line to the fenced block it stands in', () {
      // A file ends in a newline and the block's own closing fence follows on
      // the next line, so one of the two has to go.
      final resolved = _resolve('```python-assignment\n{{#include a.py}}\n```\n', {'python/a.py': 'print(...)\n'});

      expect(resolved, '```python-assignment\nprint(...)\n```\n');
    });

    test('resolves a path against the file the include is in, not the one that started it', () {
      final resolved = _resolve('{{#include steps/one.md}}\n', {
        'python/steps/one.md': '## One\n{{#include ../checks/one.py}}\n',
        'python/checks/one.py': 'ok\n',
      });

      expect(resolved, '## One\nok\n');
    });

    test('may reach a file beside the subject, and no further', () {
      expect(_resolve('{{#include ../shared.py}}', {'shared.py': 'x'}), 'x');
      expect(() => _resolve('{{#include ../../outside.py}}'), _refuses('outside the lessons'));
    });

    test('leaves a source without one exactly as it was', () {
      const source = 'print("{{naam}}")\r\n';

      expect(_resolve(source), same(source));
    });

    test('a backslash writes the line out instead', () {
      expect(_resolve(r'\{{#include a.py}}'), '{{#include a.py}}');
      expect(_resolve(r'Schrijf `\{{#include a.py}}` zo op.'), 'Schrijf `{{#include a.py}}` zo op.');
    });

    test('an include a step is made of parses as that step', () {
      final lesson = Lesson.parse(
        _resolve('# T\n\n```metadata\nid: x\n```\n\n{{#include step.md}}\n', {
          'python/step.md':
              '## S\n\n```metadata\ntype: exercise\nid: s\n```\n\nprose\n\n'
              '```python-assignment\n{{#include s.py}}\n```\n\n```python-validator\n{{#include s.check.py}}\n```\n',
          'python/s.py': 'print(...)\n',
          'python/s.check.py': 'program.allow_only("call")\n',
        }),
      );

      expect(lesson.sections.single.starter, 'print(...)');
      expect(lesson.sections.single.validator, 'program.allow_only("call")');
    });

    test('a file that is not there is refused, by both names', () {
      expect(() => _resolve('{{#include gone.py}}'), _refuses('python/les.md includes gone.py, which does not exist'));
    });

    test('a file that comes round to itself is refused', () {
      expect(
        () => _resolve('{{#include a.md}}', {'python/a.md': '{{#include b.md}}', 'python/b.md': '{{#include a.md}}'}),
        _refuses('python/les.md -> python/a.md -> python/b.md'),
      );
      expect(() => _resolve('{{#include les.md}}'), _refuses('already being included'));
    });

    test('one that shares its line is refused, rather than shown to a student', () {
      expect(() => _resolve('Zie {{#include a.py}} hier.', {'python/a.py': 'x'}), _refuses('alone on its line'));
    });

    test('part of a file cannot be asked for yet', () {
      expect(() => _resolve('{{#include a.py:2:10}}', {'python/a.py': 'x'}), _refuses('only whole files'));
      expect(() => _resolve('{{#include a.py:anchor}}', {'python/a.py': 'x'}), _refuses('only whole files'));
    });

    test('a path from the root, and no path at all, are refused', () {
      expect(() => _resolve('{{#include /etc/passwd}}'), _refuses('relative to the file'));
      expect(() => _resolve('{{#include }}'), _refuses('names no file'));
    });
  });
}
