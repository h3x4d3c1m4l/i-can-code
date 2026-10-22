import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/extensions/app_localizations_extension.dart';
import 'package:i_can_code/l10n/generated/app_localizations_en.dart';
import 'package:i_can_code/l10n/generated/app_localizations_nl.dart';
import 'package:i_can_code/services/python/python_check_library.dart';

/// Runs [expression] against the check library in whatever CPython is on this
/// machine, and reads the answer back as JSON.
///
/// The library is a plain module, so it can be asked about itself without the
/// wrapper program or a browser around it.
Object? _ask(String expression, {String prelude = ''}) {
  // Carried as base64 for the reason `buildProgram` does it: the source cannot
  // terminate the literal holding it.
  final payload = base64.encode(utf8.encode(kCheckLibrary));
  final program = '''
import base64, json
_lib = {}
exec(compile(base64.b64decode("$payload").decode("utf-8"), "checks.py", "exec"), _lib)
$prelude
print(json.dumps($expression))
''';
  final run = Process.runSync('python3', ['-c', program]);

  if (run.exitCode != 0) {
    fail('Could not ask the check library about itself:\n${run.stderr}');
  }
  return jsonDecode('${run.stdout}');
}

/// Runs `require_aaa` on [source]: null when it passes, else what it raised —
/// the test it named for Dart to phrase, and its message.
({String? test, String message})? _aaa(String source, {String? message}) {
  final payload = base64.encode(utf8.encode(jsonEncode({'source': source, 'message': message})));
  final answer = _ask(
    '_probe(**json.loads(base64.b64decode("$payload")))',
    prelude: '''
def _probe(source, message):
    try:
        _lib["analyze"](source).require_aaa(message=message)
    except Exception as e:
        return {"test": getattr(e, "icc_aaa", None), "message": str(e)}
    return None
''',
  );
  if (answer == null) return null;
  final raised = answer as Map<String, dynamic>;
  return (test: raised['test'] as String?, message: raised['message'] as String);
}

bool get _hasPython3 {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('the check library', () {
    test('names the same unphrased constructs the app has strings for', () {
      // The one coupling between a Python dict and a Dart switch. Left to drift,
      // a new construct would reach a student as a bare English word in a Dutch
      // sentence — which is the whole thing the translation is there to prevent.
      final phrased = (_ask('sorted(_lib["_PHRASES"])')! as List).cast<String>();

      expect(phrased.toSet(), kPhrasedConstructs);
    });

    test('everything else it can refuse is a real Python keyword', () {
      // What makes leaving them untranslated correct: a keyword is the same word
      // in every language, so it is set as code rather than said.
      final unphrased = (_ask(
        'sorted(set(_lib["Program"]._CONSTRUCTS) - set(_lib["_PHRASES"]))',
      )! as List).cast<String>();
      final notKeywords = (_ask(
        'sorted(c for c in set(_lib["Program"]._CONSTRUCTS) - set(_lib["_PHRASES"]) '
        'if not _lib["_is_keyword"](c))',
      )! as List).cast<String>();

      expect(unphrased, isNotEmpty);
      expect(notKeywords, isEmpty, reason: 'these need a phrase and a translation');
    });

    test('every group it offers stands for constructs it knows', () {
      final unknown = (_ask(
        'sorted(n for names in _lib["Program"]._GROUPS.values() for n in names '
        'if n not in _lib["Program"]._CONSTRUCTS)',
      )! as List).cast<String>();

      expect(unknown, isEmpty);
    });
  }, skip: _hasPython3 ? false : 'python3 is not on PATH');

  group('require_aaa', () {
    String aTest(String name, List<String> markers) =>
        'def $name():\n${markers.map((marker) => '    $marker\n    x = 1\n').join()}    pass\n';

    test('passes a test that marks its three parts in order', () {
      expect(_aaa(aTest('test_a', ['# Arrange', '# Act', '# Assert'])), isNull);
    });

    test('reads the word, not its case or what follows it', () {
      expect(_aaa(aTest('test_a', ['# ARRANGE', '#act: roep aan', '# Assert dat het klopt'])), isNull);
    });

    test('lets one comment mark the call and its check together', () {
      expect(_aaa(aTest('test_a', ['# Arrange', '# Act / Assert'])), isNull);
      expect(_aaa(aTest('test_a', ['# Arrange', '# Act en assert'])), isNull);
    });

    test('names the test that is missing a part', () {
      final raised = _aaa('${aTest('test_a', ['# Arrange', '# Act', '# Assert'])}\n${aTest('test_b', ['# Arrange', '# Assert'])}');

      expect(raised?.test, 'test_b');
      expect(raised?.message, contains('test_b'));
    });

    test('refuses a part twice, or out of order', () {
      expect(_aaa(aTest('test_a', ['# Arrange', '# Act', '# Act', '# Assert']))?.test, 'test_a');
      expect(_aaa(aTest('test_a', ['# Act', '# Arrange', '# Assert']))?.test, 'test_a');
    });

    test('does not count a word that only starts like a marker', () {
      expect(_aaa(aTest('test_a', ['# Arrange', '# Actually', '# Assert']))?.test, 'test_a');
    });

    test('does not count markers outside the test', () {
      expect(_aaa('# Arrange\n# Act\n# Assert\n${aTest('test_a', [])}')?.test, 'test_a');
    });

    test('checks the methods of a Test class, and nothing that is no test', () {
      const source = '''
def helper():
    return 1

class TestKassa:
    def test_a(self):
        x = 1
''';
      expect(_aaa(source)?.test, 'test_a');
    });

    test("the author's own message replaces the placeholder and carries no name", () {
      final raised = _aaa(aTest('test_a', []), message: 'Zet de drie commentaren erin.');

      expect(raised?.message, 'Zet de drie commentaren erin.');
      expect(raised?.test, isNull);
    });
  }, skip: _hasPython3 ? false : 'python3 is not on PATH');

  group('the refusal a student reads', () {
    test('names the test that is missing its parts, in either language', () {
      expect(AppLocalizationsNl().checkAaa('test_deel'), contains('`test_deel`'));
      expect(AppLocalizationsEn().checkAaa('test_deel'), contains('`test_deel`'));
    });

    test('sets a keyword as code and leaves it untranslated', () {
      expect(AppLocalizationsNl().checkNotAllowed('if'), contains('`if`'));
      expect(AppLocalizationsEn().checkNotAllowed('if'), contains('`if`'));
    });

    test('says a construct with no keyword in the reader\'s language', () {
      final dutch = AppLocalizationsNl().checkNotAllowed('assignment');
      final english = AppLocalizationsEn().checkNotAllowed('assignment');

      expect(dutch, contains('geen toewijzing'));
      expect(dutch, isNot(contains('assignment')));
      expect(english, contains('an assignment'));
      expect(dutch, isNot(english));
    });

    test('phrases every construct it claims to phrase, in both languages', () {
      for (final locale in [AppLocalizationsNl(), AppLocalizationsEn()]) {
        for (final construct in kPhrasedConstructs) {
          expect(
            locale.checkNotAllowed(construct),
            isNot(contains('`')),
            reason: '$construct fell through to the code-span fallback',
          );
        }
      }
    });

    test('a construct this build has no phrase for degrades instead of throwing', () {
      expect(AppLocalizationsNl().checkNotAllowed('walrus'), contains('`walrus`'));
    });
  });
}
