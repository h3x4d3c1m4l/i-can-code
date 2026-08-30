import 'dart:convert';

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

  /// Output hit the runtime's per-run cap and was cut short.
  final bool truncated;

  final Duration duration;

  const AttemptResult({
    required this.passed,
    required this.output,
    this.programError,
    this.checkMessage,
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

  final PythonRuntime _runtime;

  PythonAttemptRunner(this._runtime);

  /// Runs [code] and, if it finished cleanly, [validator]. A null or blank
  /// validator means nothing to check, which passes.
  Future<AttemptResult> attempt({required String code, String? validator}) async {
    if (!_runtime.isSupported) {
      return const AttemptResult.broken('Running code is not available in this browser.');
    }

    await _runtime.ready();
    final result = await _runtime.run(buildProgram(code: code, validator: validator));

    return parseResult(result);
  }

  /// Builds the wrapper program handed to CPython. Visible for testing.
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
_buf = io.StringIO()
_verdict = {"ok": True, "error": None, "message": None}

try:
    _compiled = compile(_p["code"], "main.py", "exec")
except SyntaxError as _e:
    _verdict["ok"] = False
    _verdict["error"] = "".join(traceback.format_exception_only(type(_e), _e))
else:
    sys.stdout = _buf
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

_captured = _buf.getvalue()

if _verdict["ok"] and _p["validator"].strip():
    # `output` is stripped of trailing whitespace on purpose: print() ends every
    # line with a newline, so an author checking `output == "42"` would never
    # pass. See docs/lesson-format.md.
    _scope = {"code": _p["code"], "output": _captured.rstrip()}
    try:
        exec(compile(_p["validator"], "validator.py", "exec"), _scope)
    except BaseException as _e:
        _verdict["ok"] = False
        _verdict["message"] = str(_e) or type(_e).__name__

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

    if (line == null) {
      // No verdict: the runtime failed before the harness ran, or output was
      // capped mid-envelope. Never report that as a wrong answer.
      return AttemptResult(
        passed: false,
        output: result.stdout,
        programError: result.stderr.isEmpty
            ? 'The program did not finish. Its output may have been too long.'
            : result.stderr,
        truncated: result.truncated,
        duration: result.duration,
      );
    }

    final verdict = jsonDecode(line.substring(sentinel.length)) as Map<String, dynamic>;

    return AttemptResult(
      passed: verdict['ok'] as bool,
      output: verdict['output'] as String? ?? '',
      programError: verdict['error'] as String?,
      checkMessage: verdict['message'] as String?,
      truncated: result.truncated,
      duration: result.duration,
    );
  }

}
