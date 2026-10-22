/// The Python that runs pytest for a section with `run: pytest`.
///
/// Separate from `kCheckLibrary` because that one promises never to run the
/// student's code, and this one exists to do exactly that. It is carried into
/// the run the same way, as base64 exec'd by `PythonAttemptRunner.buildProgram`.
///
/// pytest itself ships in `assets/python/python315.zip`; see
/// `tool/bake_pytest.py`. Off the web, the host `python3` MUST have the same
/// version installed.
///
/// `run_tests`, `TestRun` and `TestResult` are a contract with lesson authors,
/// written down in `docs/lesson-format.md`. Changing them means changing it there.
library;

// Raw for the same reason as kCheckLibrary: this is Python source.
// ignore: unnecessary_raw_strings
const String kPytestLibrary = r'''
"""Runs the student's files under pytest, and lets a validator run them again."""
import io
import os
import shutil
import sys
import tempfile

import pytest

#: The arguments every run gets, after the directory. Each one is a workaround
#: for the WASI build or for showing the output as plain text:
#: - fd capture needs os.dup2, which WASI does not have;
#: - faulthandler fails at startup with "Not supported";
#: - the cache would be written next to the student's files;
#: - the output panel cannot render colour.
ARGS = ["-q", "--tb=short", "--color=no", "--capture=sys",
        "-p", "no:faulthandler", "-p", "no:cacheprovider"]


class TestResult:
    """How one test ended. `outcome` is "passed", "failed", "error" (its fixture
    or setup raised) or "skipped"."""

    __test__ = False  # pytest would otherwise try to collect this class.

    def __init__(self, name, outcome, message):
        self.name = name
        self.outcome = outcome
        self.message = message

    @property
    def passed(self):
        return self.outcome == "passed"

    def __repr__(self):
        return "TestResult(%r, %r)" % (self.name, self.outcome)


class TestRun:
    """What one pytest run found. Index it by a test's name: `run["test_deel"]`."""

    __test__ = False

    def __init__(self, tests, errors, output, exit_code):
        self.tests = tests
        #: Collection errors, as pytest words them: a SyntaxError or failed
        #: import in a file means none of its tests ran.
        self.errors = errors
        self.output = output
        self.exit_code = exit_code

    @property
    def passed(self):
        """At least one test ran, and none failed or errored."""
        return self.exit_code == 0 and bool(self.tests) and not self.errors

    @property
    def failed(self):
        """The names of the tests that failed or errored."""
        return [t.name for t in self.tests if t.outcome in ("failed", "error")]

    def __getitem__(self, name):
        for test in self.tests:
            if test.name == name:
                return test
        raise KeyError("no test %r; there is %s" % (name, ", ".join(t.name for t in self.tests)))

    def __iter__(self):
        return iter(self.tests)

    def __len__(self):
        return len(self.tests)

    def __bool__(self):
        # `if run_tests(...):` reads as "if it passed" to one author and "if it
        # ran" to the next, and either guess is silently wrong half the time.
        raise TypeError("a TestRun is not true or false; ask for .passed")

    def __repr__(self):
        return "TestRun(%d tests, failed=%r, errors=%d)" % (len(self.tests), self.failed, len(self.errors))


def _message(report):
    crash = getattr(report.longrepr, "reprcrash", None)
    if crash is not None:
        return crash.message
    # A skip's longrepr is (path, line, reason).
    if isinstance(report.longrepr, tuple):
        return report.longrepr[2]
    return str(report.longrepr) if report.longrepr else None


class _Collector:
    """A pytest plugin that keeps each test's outcome as it is reported."""

    def __init__(self):
        self.tests = {}
        self.errors = []

    def pytest_runtest_logreport(self, report):
        name = report.nodeid.split("::", 1)[-1]
        if report.when == "call":
            self.tests[name] = TestResult(name, report.outcome, _message(report))
        elif report.failed and (name not in self.tests or self.tests[name].passed):
            self.tests[name] = TestResult(name, "error", _message(report))
        elif report.skipped and name not in self.tests:
            self.tests[name] = TestResult(name, "skipped", _message(report))

    def pytest_collectreport(self, report):
        if report.failed:
            self.errors.append(report.longreprtext)


def _forget(names):
    # Without this a second run imports the module the first one left behind,
    # and a mutant would be tested as the original.
    for name in names:
        sys.modules.pop(name, None)


def _run(files):
    """Writes `files` (name -> source) to a fresh directory and runs pytest on it."""
    # Real, because pytest names a file relative to the working directory, and
    # through macOS's /var -> /private/var link every name became ../../../var/...
    root = os.path.realpath(tempfile.mkdtemp(prefix="icc-"))
    modules = [name[:-3] for name in files] + ["conftest"]
    ini = os.path.join(root, "pytest.ini")
    collector = _Collector()
    out = io.StringIO()
    saved = (list(sys.path), os.getcwd(), sys.stdout, sys.dont_write_bytecode, dict(os.environ))
    try:
        for name, source in files.items():
            with open(os.path.join(root, name), "w", encoding="utf-8") as f:
                f.write(source)
        # An ini of its own, so nothing above the directory configures the run.
        with open(ini, "w", encoding="utf-8") as f:
            f.write("[pytest]\n")
        _forget(modules)
        os.chdir(root)
        os.environ["PYTEST_DISABLE_PLUGIN_AUTOLOAD"] = "1"
        os.environ["COLUMNS"] = "80"
        os.environ.pop("PYTEST_ADDOPTS", None)
        sys.dont_write_bytecode = True
        sys.stdout = out
        exit_code = pytest.main([root, "-c", ini, "--rootdir", root] + ARGS, plugins=[collector])
    finally:
        sys.path[:], cwd, sys.stdout, sys.dont_write_bytecode, environ = saved
        os.chdir(cwd)
        os.environ.clear()
        os.environ.update(environ)
        _forget(modules)
        shutil.rmtree(root, ignore_errors=True)
    return TestRun(list(collector.tests.values()), collector.errors, out.getvalue(), int(exit_code))


def make_run_tests(base):
    """The `run_tests` a validator is given, starting from the student's files."""

    def run_tests(replace=None, files=None):
        """Runs pytest again on the student's files, changed first.

            run_tests(replace={"rekenmachine.py": ("if b == 0", "if b == 1")})
            run_tests(replace={"rekenmachine.py": [("+", "-"), ("<", "<=")]})
            run_tests(files={"rekenmachine.py": "def deel(a, b): ..."})

        `files` adds or replaces whole files. `replace` then changes every
        occurrence of each `old` in that file, and raises ValueError when `old`
        does not occur, so a mutant with a typo cannot pass for one that is
        caught. Returns a `TestRun`.
        """
        current = dict(base)
        current.update(files or {})
        for name, edits in (replace or {}).items():
            if name not in current:
                raise ValueError("run_tests: no file %r; there is %s" % (name, ", ".join(sorted(current))))
            source = current[name]
            for old, new in [edits] if isinstance(edits, tuple) else edits:
                if old not in source:
                    raise ValueError("run_tests: %r does not occur in %s" % (old, name))
                source = source.replace(old, new)
            current[name] = source
        return _run(current)

    return run_tests
''';
