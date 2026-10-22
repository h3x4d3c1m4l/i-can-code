import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';

import '../support/host_python.dart';

const String _module = '''
def deel(a, b):
    if b == 0:
        raise ValueError("delen door nul")
    return a / b
''';

const String _goodTests = '''
import pytest
from rekenmachine import deel


def test_deel():
    # Arrange
    a, b = 7, 2
    # Act
    uitkomst = deel(a, b)
    # Assert
    assert uitkomst == 3.5


def test_deel_door_nul():
    # Arrange
    a = 1
    # Act / Assert
    with pytest.raises(ValueError):
        deel(a, 0)
''';

/// Runs [tests] as the student's `test_rekenmachine.py`, beside [_module].
Future<AttemptResult> _attempt(String tests, {String? validator, Map<String, String>? files}) => attempt(
  code: tests,
  validator: validator,
  mode: PythonRunMode.pytest,
  fileName: 'test_rekenmachine.py',
  files: files ?? const {'rekenmachine.py': _module},
);

void main() {
  group('a pytest run', () {
    test('passes when every test does, and lists them all', () async {
      final result = await _attempt(_goodTests);

      expect(result.passed, isTrue, reason: '${result.programError ?? result.checkMessage}');
      expect(result.tests.map((test) => (test.name, test.kind)), [
        ('test_deel', TestOutcomeKind.passed),
        ('test_deel_door_nul', TestOutcomeKind.passed),
      ]);
      expect(result.output, contains('2 passed'));
    });

    test('reports each way a test can end', () async {
      final result = await _attempt('''
import pytest

@pytest.fixture
def kapot():
    raise RuntimeError("fixture")

def test_goed():
    assert True

def test_fout():
    assert len("ab") == 3

def test_fixture(kapot):
    assert True

@pytest.mark.skip(reason="later")
def test_later():
    assert True
''');

      expect(result.passed, isFalse);
      expect(result.programError, isNull, reason: 'a failing test is a wrong answer, not a crash');
      expect(result.testsProblem, TestsProblem.failing);
      expect({for (final test in result.tests) test.name: test.kind}, {
        'test_goed': TestOutcomeKind.passed,
        'test_fout': TestOutcomeKind.failed,
        'test_fixture': TestOutcomeKind.error,
        'test_later': TestOutcomeKind.skipped,
      });
      expect(result.tests.firstWhere((test) => test.name == 'test_fout').message, contains('assert 2 == 3'));
    });

    test('says so when there are no tests to run', () async {
      final result = await _attempt('from rekenmachine import deel\n');

      expect(result.passed, isFalse);
      expect(result.testsProblem, TestsProblem.none);
    });

    test('a file pytest cannot collect is a crash, with the reason', () async {
      final result = await _attempt('from rekenmachine import vermenigvuldig\n\ndef test_x():\n    assert True\n');

      expect(result.passed, isFalse);
      expect(result.programError, contains('ImportError'));
    });

    test("a SyntaxError in the student's file is a crash before pytest starts", () async {
      final result = await _attempt('def test_x(:\n    pass\n');

      expect(result.programError, contains('SyntaxError'));
      expect(result.tests, isEmpty);
    });

    test('writes no colour codes into the output', () async {
      final result = await _attempt('def test_x():\n    assert [1, 2] == [1, 3]\n');

      expect(result.output, contains('assert [1, 2] == [1, 3]'));
      expect(result.output, isNot(contains('\x1b[')));
    });

    test('the validator only runs once every test passes', () async {
      final result = await _attempt(
        'def test_x():\n    assert False\n',
        validator: 'raise Exception("validator ran")',
      );

      expect(result.checkMessage, isNull);
      expect(result.testsProblem, TestsProblem.failing);
    });

    test("an unmessaged require_aaa names the test for Dart to phrase", () async {
      final result = await _attempt(
        'from rekenmachine import deel\n\ndef test_deel():\n    assert deel(4, 2) == 2\n',
        validator: 'program.require_aaa()',
      );

      expect(result.passed, isFalse);
      expect(result.aaaTest, 'test_deel');
    });
  }, skip: hasPytest ? false : 'python3 cannot import pytest; pip install pytest==$kPytestVersion');

  group('run_tests', () {
    const mutants = '''
for old, new, hint in [("if b == 0", "if b == 1", "Test ook delen door 0."),
                       ("return a / b", "return a // b", "Test een deling met een rest.")]:
    if run_tests(replace={"rekenmachine.py": (old, new)}).passed:
        raise Exception(hint)
''';

    test('tests that catch every mutant pass', () async {
      final result = await _attempt(_goodTests, validator: mutants);

      expect(result.passed, isTrue, reason: '${result.programError ?? result.checkMessage}');
    });

    test('a mutant that slips through gives its hint', () async {
      final result = await _attempt('''
from rekenmachine import deel

def test_deel():
    assert deel(8, 2) == 4
''', validator: mutants);

      expect(result.checkMessage, 'Test ook delen door 0.');
    });

    test('a mutant whose old text is not in the file is an error, not a pass', () async {
      final result = await _attempt(
        _goodTests,
        validator: 'run_tests(replace={"rekenmachine.py": ("b == 9", "b == 1")})',
      );

      expect(result.checkMessage, contains('does not occur'));
    });

    test('a second run does not reuse the module the first one imported', () async {
      final result = await _attempt(_goodTests, validator: '''
mutant = run_tests(replace={"rekenmachine.py": ("return a / b", "return a * b")})
original = run_tests()
if mutant.passed or not original.passed:
    raise Exception("stale: %r %r" % (mutant, original))
''');

      expect(result.passed, isTrue, reason: '${result.checkMessage}');
    });

    test('whole files can be replaced, and a result is indexed by test name', () async {
      final result = await _attempt(_goodTests, validator: '''
run = run_tests(files={"rekenmachine.py": "def deel(a, b):\\n    return a / b\\n"})
if run["test_deel_door_nul"].passed or not run["test_deel"].passed:
    raise Exception(repr(run.tests))
''');

      expect(result.passed, isTrue, reason: '${result.checkMessage}');
    });

    test('a run is not true or false, so a validator cannot misread one', () async {
      final result = await _attempt(_goodTests, validator: 'if run_tests():\n    pass\n');

      expect(result.checkMessage, contains('.passed'));
    });
  }, skip: hasPytest ? false : 'python3 cannot import pytest; pip install pytest==$kPytestVersion');
}
