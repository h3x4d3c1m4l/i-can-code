// The web host is the only one that exists; everything else — the Dart VM a
// `flutter test` runs on included — falls through to the stub, which reports
// `isSupported == false` rather than throwing.
//
// A conditional import resolves the URI of whichever clause matches, so a clause
// MUST NOT be added before the file it names exists: on the VM the missing file
// would be a compile error for every test that reaches this library.
import 'package:i_can_code/services/python/python_runtime_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/python/python_runtime_web.dart' as impl;

/// What one run of a program produced.
class PythonResult {

  final String stdout;
  final String stderr;

  /// 0 when the program finished normally. Anything else means it raised, and
  /// [stderr] holds the traceback.
  final int exitCode;

  /// Output hit the per-run cap and was cut short. Surfaced to the student, so
  /// a runaway loop does not read as a program that stopped early.
  final bool truncated;

  final Duration duration;

  const PythonResult({
    required this.stdout,
    required this.stderr,
    this.exitCode = 0,
    this.truncated = false,
    this.duration = Duration.zero,
  });

  const PythonResult.failure(String message)
      : stdout = '',
        stderr = message,
        exitCode = 1,
        truncated = false,
        duration = Duration.zero;

  bool get succeeded => exitCode == 0;

}

/// Runs Python, wherever this build happens to be running.
///
/// The artifact — CPython built for wasm32-wasi — is the same everywhere; only
/// the host that executes it differs.
abstract class PythonRuntime {

  /// False where no host is available. The UI stays usable but cannot run.
  bool get isSupported;

  /// What the interpreter calls itself — "Python 3.14.0" — asked of the build
  /// that is actually loaded rather than written down anywhere in the app, so a
  /// screen naming it cannot drift from what runs the student's code.
  ///
  /// Null until [ready] has completed, and wherever there is no host to ask.
  /// A runtime that cannot name itself still runs code, so a caller MUST have
  /// something to show in its place.
  String? get version;

  /// Loads the interpreter. Safe to call repeatedly; only the first does work.
  Future<void> ready();

  /// Runs [code] to completion, feeding [stdin] to `input()`.
  ///
  /// Never throws for a *program* error: a traceback comes back in
  /// [PythonResult.stderr] with a non-zero exit code.
  Future<PythonResult> run(String code, {String stdin});

  /// Stops a running program. MUST NOT depend on the program cooperating — it
  /// is the only thing that ends `while True:`.
  ///
  /// A [run] in flight resolves rather than hanging, but with nothing worth
  /// reading: whatever the program had printed died with the process holding it,
  /// so a caller that stopped on purpose should drop that answer rather than
  /// show it as a verdict.
  Future<void> cancel();

  void dispose();

}

/// The runtime for this platform.
PythonRuntime createPythonRuntime() => impl.createPythonRuntime();
