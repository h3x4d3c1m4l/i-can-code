import 'dart:convert';

import 'package:i_can_code/services/python/python_check_library.dart';
import 'package:i_can_code/services/python/python_pytest_library.dart';
import 'package:i_can_code/services/python/python_runtime.dart';

/// How a section's code is run.
enum PythonRunMode {
  /// As a program, the way a student would run `python main.py`.
  script,

  /// Under pytest, with the section's files beside it.
  pytest,
}

/// How one test ended, in a [PythonRunMode.pytest] run.
enum TestOutcomeKind {
  passed,
  failed,

  /// Its setup or teardown raised, so the test itself never decided anything.
  error,
  skipped,
}

/// One test of a [PythonRunMode.pytest] run.
class TestOutcome {

  /// As pytest names it within its file: `test_deel`, `TestRekenmachine::test_deel`
  /// or `test_deel[3-0]`.
  final String name;

  final TestOutcomeKind kind;

  /// pytest's one-line reason, such as `assert 4 == 5`. Null for a pass.
  final String? message;

  const TestOutcome({required this.name, required this.kind, this.message});

  factory TestOutcome.fromJson(Map<String, dynamic> json) => TestOutcome(
    name: json['name'] as String,
    kind: TestOutcomeKind.values.byName(json['outcome'] as String),
    message: json['message'] as String?,
  );

}

/// Why a [PythonRunMode.pytest] run failed before its validator ran.
enum TestsProblem {
  /// pytest collected no tests.
  none,

  /// At least one test failed or errored.
  failing,
}

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

  /// The test `require_aaa` refused, when the author wrote no message of their
  /// own. A name for the same reason as [disallowedConstruct].
  final String? aaaTest;

  /// Every test of a [PythonRunMode.pytest] run, passed or not. Empty for a
  /// script.
  final List<TestOutcome> tests;

  /// Set when a [PythonRunMode.pytest] run failed on its tests, before the
  /// validator could run.
  final TestsProblem? testsProblem;

  /// Output hit the runtime's per-run cap and was cut short.
  final bool truncated;

  /// The files the student's program created or changed, by path, as they
  /// stood before the checks ran. A file the lesson gave and the program left
  /// alone is not among them.
  final List<WrittenFile> writtenFiles;

  /// The program wrote more than [writtenFiles] holds: past the cap on how
  /// many are listed, or past the room left in the run's output.
  final bool filesCut;

  final Duration duration;

  const AttemptResult({
    required this.passed,
    required this.output,
    this.programError,
    this.checkMessage,
    this.disallowedConstruct,
    this.aaaTest,
    this.tests = const [],
    this.testsProblem,
    this.truncated = false,
    this.writtenFiles = const [],
    this.filesCut = false,
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
      aaaTest = null,
      tests = const [],
      testsProblem = null,
      truncated = false,
      writtenFiles = const [],
      filesCut = false,
      duration = Duration.zero;

}

/// One file a run left behind in the program's working directory.
class WrittenFile {

  /// Relative to the working directory, with `/` between folders.
  final String path;

  /// The file's text, or the start of it when [truncated]. Null when the file
  /// is not UTF-8 text, which has nothing to show.
  final String? text;

  /// The whole file's size in bytes, however much of it [text] holds.
  final int size;

  final bool truncated;

  /// A file the lesson gave, which the program changed.
  final bool changed;

  const WrittenFile({
    required this.path,
    required this.text,
    required this.size,
    this.truncated = false,
    this.changed = false,
  });

  /// The file's own name, without the folders it is in.
  String get name => path.split('/').last;

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

  /// Marks the line after the verdict that lists the files the program wrote.
  /// A line of its own, so a cap that cuts it costs the files and never the
  /// verdict. Not prefixed by [sentinel], which would make it read as one.
  static const String filesSentinel = '__ICC_FILES__';

  /// What the runtime keeps of a run's stdout, in bytes. MUST match
  /// `MAX_OUTPUT_BYTES` in `web/python/python_worker.js`.
  static const int outputCap = 256 * 1024;

  /// The most the files line may take, in bytes, however much room is left.
  static const int _filesCap = 64 * 1024;

  /// [kCheckLibrary], carried the same way the student's code is. Encoded once
  /// rather than per attempt: it is a constant and every run gets the same bytes.
  static final String _encodedChecks = base64.encode(utf8.encode(kCheckLibrary));

  /// [kPytestLibrary], carried the same way.
  static final String _encodedPytest = base64.encode(utf8.encode(kPytestLibrary));

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
  ///
  /// [files] are written into the program's working directory, by name, before
  /// it starts. Every attempt gets them as given, whatever the last one did.
  ///
  /// [mode] and [fileName] are as for [buildProgram].
  Future<AttemptResult> attempt({
    required String code,
    String? validator,
    String? stdin,
    Map<String, String> files = const {},
    PythonRunMode mode = PythonRunMode.script,
    String fileName = 'main.py',
  }) async {
    if (!_runtime.isSupported) {
      return const AttemptResult.broken('Running code is not available in this browser.');
    }

    await _runtime.ready();
    final result = await _runtime.run(
      buildProgram(code: code, validator: validator, files: files, mode: mode, fileName: fileName),
      stdin: stdin ?? '',
    );

    return parseResult(result);
  }

  /// Builds the wrapper program handed to CPython. Visible for testing.
  ///
  /// The validator's scope gets `code` and `output`, plus [kCheckLibrary]'s own
  /// names and a `program` already reading the student's source as a tree.
  ///
  /// The student's source, the validator and [files] MUST be carried as
  /// **base64 of a JSON document**, never interpolated: base64's alphabet
  /// contains no quote, so the payload cannot terminate the literal holding it.
  ///
  /// With [PythonRunMode.pytest], [code] is the file named [fileName], and
  /// pytest runs on it and [files] instead of [code] running as a script. The
  /// validator only runs once every test passed, and also gets `results` and
  /// `run_tests`; see [kPytestLibrary].
  static String buildProgram({
    required String code,
    String? validator,
    Map<String, String> files = const {},
    PythonRunMode mode = PythonRunMode.script,
    String fileName = 'main.py',
  }) {
    final payload = base64.encode(
      utf8.encode(jsonEncode({'code': code, 'validator': validator ?? '', 'files': files, 'file': fileName})),
    );

    return '''
import base64, codecs, gc, io, json, linecache, os, sys, traceback

# Off for the browser already. The host scripts run python3 without -B, and a
# module imported from the working directory would leave a __pycache__ behind
# that reads as a file the student wrote.
sys.dont_write_bytecode = True
_p = json.loads(base64.b64decode("$payload").decode("utf-8"))
# The code is compiled under its file name, "main.py" unless a pytest step names
# another, and CPython reads a traceback's lines, and a
# SyntaxError's text and column, back from the file by that name. The browser runs
# this wrapper as main.py, so every error quoted a line of the harness. The script
# is already parsed, so the file can hold what was actually compiled.
try:
    with open(_p["file"], "w", encoding="utf-8") as _f:
        _f.write(_p["code"])
except OSError:
    # mtime None keeps linecache.checkcache from dropping the entry.
    linecache.cache[_p["file"]] = (len(_p["code"]), None, _p["code"].splitlines(True), _p["file"])
_root = os.getcwd()
for _name, _text in _p["files"].items():
    # newline="" writes the text as the lesson has it, on a host that would
    # otherwise turn every \\n into \\r\\n.
    with open(_name, "w", encoding="utf-8", newline="") as _f:
        _f.write(_text)
# Everything here before the program starts that is not the lesson's: the code,
# and in the browser the standard library and /tmp. None of it is shown.
_harness = set(os.listdir(_root)) - set(_p["files"])
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


def _collect():
    # What the program left in its working directory, as it stood before the
    # checks ran. Bounded in files and in entries looked at, because creating an
    # empty file costs a program nothing.
    found = []
    more = False
    visited = 0
    for here, folders, names in os.walk(_root):
        at = os.path.relpath(here, _root)
        if at == ".":
            folders[:] = [f for f in folders if f not in _harness]
            names = [n for n in names if n not in _harness]
        folders.sort()
        for name in sorted(names):
            visited += 1
            path = name if at == "." else at.replace(os.sep, "/") + "/" + name
            if len(found) >= 50 or visited > 2000:
                more = True
                continue
            full = os.path.join(here, name)
            size = os.path.getsize(full)
            with open(full, "rb") as f:
                data = f.read($_filesCap)
            seed = _p["files"].get(path)
            if seed is not None and data == seed.encode("utf-8") and size == len(data):
                continue
            text = None
            if b"\\0" not in data:
                try:
                    # Not final while bytes are left: a character cut in half at
                    # the end of what was read is dropped, not called broken.
                    text = codecs.getincrementaldecoder("utf-8")().decode(data, final=len(data) == size)
                except UnicodeDecodeError:
                    pass
            found.append({
                "path": path,
                "text": text,
                "size": size,
                "truncated": text is not None and len(data) < size,
                "changed": seed is not None,
            })
    return found, more


def _fit(found, more, room):
    # As much of every file as fits in [room] bytes of JSON, in order. With
    # ensure_ascii on, a character of JSON is a byte.
    kept = []
    for entry in found:
        cost = len(json.dumps(entry)) + 2
        if cost > room and entry["text"]:
            text = entry["text"]
            while text and len(json.dumps(dict(entry, text=text, truncated=True))) + 2 > room:
                text = text[: len(text) * 3 // 4]
            entry = dict(entry, text=text, truncated=True)
            cost = len(json.dumps(entry)) + 2
        if cost > room:
            more = True
            break
        kept.append(entry)
        room -= cost
    return json.dumps({"files": kept, "more": more})


${mode == PythonRunMode.pytest ? _pytestRun : _scriptRun}
# What `python main.py` does on its way out. A file the program opened and never
# closed is flushed once nothing holds it, and would otherwise be read back
# empty. Anything printed on the way is dropped, as it would be after the end.
sys.stdout = io.StringIO()
try:
    _g.clear()
    gc.collect()
except BaseException:
    pass
finally:
    sys.stdout = _out
# A program that changed directory would move the checks' relative paths too.
try:
    os.chdir(_root)
except OSError:
    pass

try:
    _found, _more = _collect()
except BaseException:
    _found, _more = [], True

_captured = _buf.getvalue()

if _verdict["ok"] and _p["validator"].strip():
    # `output` is stripped of trailing whitespace on purpose: print() ends every
    # line with a newline, so an author checking `output == "42"` would never
    # pass. See docs/lesson-format.md.
    _scope = {"code": _p["code"], "output": _captured.rstrip(), **_extra}
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
        # Set only by the check library's NotAllowed and AaaMissing, so the
        # message above stays the author's whenever they wrote one.
        _verdict["notAllowed"] = getattr(_e, "icc_construct", None)
        _verdict["aaa"] = getattr(_e, "icc_aaa", None)

_verdict["output"] = _captured
_line = "\\n$sentinel" + json.dumps(_verdict) + "\\n"
_out.write(_line)
# The verdict is written first and as it always was, so a cap that falls in the
# files costs only the files. The slack is for what the program wrote to the
# real stdout, which nothing here counted.
_room = min($_filesCap, $outputCap - len(_line) - len("$filesSentinel") - 8192)
try:
    _listed = _fit(_found, _more, _room)
except BaseException:
    _listed = json.dumps({"files": [], "more": True})
_out.write("$filesSentinel" + _listed + "\\n")
''';
  }

  /// Runs the student's code as a script. Leaves `_verdict`, the program's
  /// globals in `_g`, what it printed in `_buf`, and `_extra` for the
  /// validator's scope.
  static const String _scriptRun = '''
_verdict = {"ok": True, "error": None, "message": None}
_g = {"__name__": "__main__"}
_extra = {}

try:
    _compiled = compile(_p["code"], _p["file"], "exec")
except SyntaxError as _e:
    _verdict["ok"] = False
    _verdict["error"] = "".join(traceback.format_exception_only(type(_e), _e))
else:
    sys.stdout = _buf
    sys.stdin = _Echo(_in)
    try:
        exec(_compiled, _g)
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
''';

  /// Runs pytest on the student's file and the section's files. Leaves the same
  /// names as [_scriptRun], with pytest's report in `_buf`.
  ///
  /// A test that fails is a failed check and not a crash: in either kind of
  /// exercise it means the student's half is wrong. What does count as a crash
  /// is a file pytest cannot collect, because no test in it ran at all.
  static final String _pytestRun = '''
_verdict = {"ok": True, "error": None, "message": None, "tests": []}
_g = {}
_extra = {}

try:
    compile(_p["code"], _p["file"], "exec")
except SyntaxError as _e:
    _verdict["ok"] = False
    _verdict["error"] = "".join(traceback.format_exception_only(type(_e), _e))
else:
    _plib = {}
    try:
        exec(compile(base64.b64decode("$_encodedPytest").decode("utf-8"), "pytest_checks.py", "exec"), _plib)
    except ImportError as _e:
        _verdict["ok"] = False
        _verdict["error"] = "pytest is not available in this Python: %s" % _e
    else:
        _files = dict(_p["files"])
        _files[_p["file"]] = _p["code"]
        _results = _plib["_run"](_files)
        _buf.write(_results.output)
        _verdict["tests"] = [{"name": _t.name, "outcome": _t.outcome, "message": _t.message} for _t in _results.tests]
        if _results.errors:
            _verdict["ok"] = False
            _verdict["error"] = "\\n".join(_results.errors)
        elif not _results.tests:
            _verdict["ok"] = False
            _verdict["testsProblem"] = "none"
        elif not _results.passed:
            _verdict["ok"] = False
            _verdict["testsProblem"] = "failing"
        else:
            _extra = {"results": _results, "run_tests": _plib["make_run_tests"](_files)}
''';

  /// Reads the verdict back out of a run.
  ///
  /// Visible for testing.
  static AttemptResult parseResult(PythonResult result) {
    final lines = result.stdout.split('\n');
    final at = lines.lastIndexWhere((line) => line.startsWith(sentinel));
    final line = at < 0 ? null : lines[at];

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

    // Only a line after the verdict is the harness's: the program could have
    // written one of its own to the real stdout before it.
    final listing = lines.skip(at + 1).where((line) => line.startsWith(filesSentinel)).lastOrNull;
    final (files, filesCut) = _readFiles(listing, cut: result.truncated);

    return AttemptResult(
      passed: verdict['ok'] as bool,
      output: verdict['output'] as String? ?? '',
      programError: verdict['error'] as String?,
      checkMessage: verdict['message'] as String?,
      disallowedConstruct: verdict['notAllowed'] as String?,
      aaaTest: verdict['aaa'] as String?,
      tests: [
        for (final test in verdict['tests'] as List<dynamic>? ?? const []) TestOutcome.fromJson(test as Map<String, dynamic>),
      ],
      testsProblem: switch (verdict['testsProblem']) {
        final String problem => TestsProblem.values.byName(problem),
        _ => null,
      },
      // The verdict carries the whole output, so the cap can only have cut
      // what came after it: the files, which say so themselves.
      writtenFiles: files,
      filesCut: filesCut,
      duration: result.duration,
    );
  }

  /// Reads the files line, if there is a whole one. Without it the files are
  /// cut when the run's output was, and there were none to cut otherwise.
  static (List<WrittenFile>, bool) _readFiles(String? line, {required bool cut}) {
    if (line == null) return (const [], cut);

    try {
      final listing = jsonDecode(line.substring(filesSentinel.length)) as Map<String, dynamic>;
      final files = [
        for (final entry in (listing['files'] as List).cast<Map<String, dynamic>>())
          WrittenFile(
            path: entry['path'] as String,
            text: entry['text'] as String?,
            size: entry['size'] as int,
            truncated: entry['truncated'] as bool,
            changed: entry['changed'] as bool,
          ),
      ];
      return (files, listing['more'] as bool);
    } on Object {
      return (const [], true);
    }
  }

}
