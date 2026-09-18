import 'dart:convert';

import 'package:i_can_code/services/python/python_check_library.dart';
import 'package:i_can_code/services/python/python_runtime.dart';

/// What one attempt at an assignment produced.
class AttemptResult {

  /// The program ran and every check passed.
  final bool passed;

  /// What the student's program printed, verbatim — so it keeps its trailing
  /// newline, unlike the `output` a validator sees.
  final String output;

  /// The student's program raised. Their traceback, with the harness's own
  /// frames removed. Null when the program finished normally.
  final String? programError;

  /// A check failed: the message the validator raised, written for the student.
  /// Null when every check passed.
  final String? checkMessage;

  /// The construct a step refused — `if`, `assignment`, … — when the check that
  /// failed was `disallow` or `allow_only` and the lesson author wrote no
  /// message of their own. Null otherwise, including when they did.
  ///
  /// It travels as a name rather than a sentence so it can be said in the
  /// reader's language; [checkMessage] still carries the English placeholder for
  /// anything with no localizations to reach for, such as `tool/try_lesson.dart`.
  final String? disallowedConstruct;

  /// Output hit the runtime's per-run cap and was cut short.
  final bool truncated;

  final Duration duration;

  const AttemptResult({
    required this.passed,
    required this.output,
    this.programError,
    this.checkMessage,
    this.disallowedConstruct,
    this.truncated = false,
    this.duration = Duration.zero,
  });

  /// The harness itself failed — the runtime is unavailable, or its answer was
  /// unreadable. MUST NOT be phrased as a student mistake.
  const AttemptResult.broken(String message)
    : passed = false,
      output = '',
      programError = message,
      checkMessage = null,
      disallowedConstruct = null,
      truncated = false,
      duration = Duration.zero;

}

/// Runs a student's code and then the section's hidden checks, in one go.
///
/// One [PythonRuntime.run] rather than two: the checks MUST see the exact output
/// that run produced, and a second run can differ. `docs/lesson-format.md`
/// promises validator authors the same interpreter.
class PythonAttemptRunner {

  /// Marks the harness's own line on stdout, for output that escapes the
  /// capture buffer — a write to `sys.__stdout__`, or a C-level write.
  static const String sentinel = '__ICC_VERDICT__';

  /// [kCheckLibrary], carried the same way the student's code is. Encoded once
  /// rather than per attempt: it is a constant and every run gets the same bytes.
  static final String _encodedChecks = base64.encode(utf8.encode(kCheckLibrary));

  final PythonRuntime _runtime;

  PythonAttemptRunner(this._runtime);

  /// Runs [code] and, if it finished cleanly, [validator]. A null or blank
  /// validator means nothing to check, which passes.
  ///
  /// [stdin] is what the program reads on standard input. It travels on the real
  /// file descriptor rather than inside the program text, so `input()` and
  /// `sys.stdin` behave the way a student would find them anywhere else, and
  /// [buildProgram] stays the one string that is the whole experiment. A program
  /// that reads past the end of it stops with `EOFError`, which comes back as a
  /// [AttemptResult.programError] and never as a failed check.
  Future<AttemptResult> attempt({required String code, String? validator, String? stdin}) async {
    if (!_runtime.isSupported) {
      return const AttemptResult.broken('Running code is not available in this browser.');
    }

    await _runtime.ready();
    final result = await _runtime.run(buildProgram(code: code, validator: validator), stdin: stdin ?? '');

    return parseResult(result);
  }

  /// Builds the wrapper program handed to CPython. Visible for testing.
  ///
  /// The validator's scope gets `code` and `output`, plus [kCheckLibrary]'s own
  /// names and a `program` already reading the student's source as a tree.
  ///
  /// The student's source and the validator MUST be carried as **base64 of a
  /// JSON document**, never interpolated: base64's alphabet contains no quote,
  /// so the payload cannot terminate the literal holding it.
  static String buildProgram({required String code, String? validator}) {
    final payload = base64.encode(
      utf8.encode(jsonEncode({'code': code, 'validator': validator ?? ''})),
    );

    return '''
import base64, io, json, sys, traceback

_p = json.loads(base64.b64decode("$payload").decode("utf-8"))
_out = sys.stdout
_in = sys.stdin
_buf = io.StringIO()


class _Echo:
    # A terminal shows what is typed, and pressing Enter starts a new line.
    # Scripted input does neither, so `input("Naam? ")` and the next print would
    # run together on one line in a way no student sees in PyCharm. This writes
    # each line into the output as it is read. It wraps stdin rather than
    # `input`: at the end of the script CPython's own `input` raises the
    # EOFError, so no frame of the harness reaches the student's traceback.
    def __init__(self, real):
        self._real = real

    def readline(self, *args):
        line = self._real.readline(*args)
        sys.stdout.write(line)
        return line

    def read(self, *args):
        text = self._real.read(*args)
        sys.stdout.write(text)
        return text

    def __iter__(self):
        return self

    def __next__(self):
        line = self.readline()
        if not line:
            raise StopIteration
        return line

    def __getattr__(self, name):
        return getattr(self._real, name)

_verdict = {"ok": True, "error": None, "message": None}

try:
    _compiled = compile(_p["code"], "main.py", "exec")
except SyntaxError as _e:
    _verdict["ok"] = False
    _verdict["error"] = "".join(traceback.format_exception_only(type(_e), _e))
else:
    sys.stdout = _buf
    sys.stdin = _Echo(_in)
    try:
        exec(_compiled, {"__name__": "__main__"})
    except SystemExit:
        pass
    except BaseException as _e:
        # tb_next drops this harness's own exec frame, so the student sees only
        # the lines they wrote.
        _verdict["ok"] = False
        _verdict["error"] = "".join(
            traceback.format_exception(type(_e), _e, _e.__traceback__.tb_next)
        )
    finally:
        sys.stdout = _out
        sys.stdin = _in

_captured = _buf.getvalue()

if _verdict["ok"] and _p["validator"].strip():
    # `output` is stripped of trailing whitespace on purpose: print() ends every
    # line with a newline, so an author checking `output == "42"` would never
    # pass. See docs/lesson-format.md.
    _scope = {"code": _p["code"], "output": _captured.rstrip()}
    try:
        # Inside the try on purpose: a broken library must surface as a check
        # that failed, not as a run that produced no verdict at all.
        _lib = {}
        exec(compile(base64.b64decode("$_encodedChecks").decode("utf-8"), "checks.py", "exec"), _lib)
        _scope.update({_n: _lib[_n] for _n in _lib["__all__"]})
        _scope["program"] = _lib["analyze"](_p["code"])
        exec(compile(_p["validator"], "validator.py", "exec"), _scope)
    except BaseException as _e:
        _verdict["ok"] = False
        _verdict["message"] = str(_e) or type(_e).__name__
        # Set only by the check library's NotAllowed, so the message above stays
        # the author's whenever they wrote one.
        _verdict["notAllowed"] = getattr(_e, "icc_construct", None)

_verdict["output"] = _captured
_out.write("\\n$sentinel" + json.dumps(_verdict) + "\\n")
''';
  }

  /// Reads the verdict back out of a run.
  ///
  /// Visible for testing.
  static AttemptResult parseResult(PythonResult result) {
    final line = result.stdout
        .split('\n')
        .reversed
        .where((line) => line.startsWith(sentinel))
        .firstOrNull;

    // No usable verdict: the runtime failed before the harness ran, or output
    // was capped mid-envelope. Never report that as a wrong answer.
    AttemptResult unreadable() => AttemptResult(
      passed: false,
      output: result.stdout,
      programError: result.stderr.isEmpty
          ? 'The program did not finish. Its output may have been too long.'
          : result.stderr,
      truncated: result.truncated,
      duration: result.duration,
    );

    if (line == null) return unreadable();

    final Map<String, dynamic> verdict;
    try {
      // The cap can fall *inside* the envelope, leaving a line that opens with
      // the sentinel and carries half a JSON document. Without this, the
      // FormatException escapes and the run never finishes at all: the button
      // keeps spinning and the student is given nothing to act on.
      verdict = jsonDecode(line.substring(sentinel.length)) as Map<String, dynamic>;
    } on Object {
      return unreadable();
    }

    return AttemptResult(
      passed: verdict['ok'] as bool,
      output: verdict['output'] as String? ?? '',
      programError: verdict['error'] as String?,
      checkMessage: verdict['message'] as String?,
      disallowedConstruct: verdict['notAllowed'] as String?,
      truncated: result.truncated,
      duration: result.duration,
    );
  }

}
