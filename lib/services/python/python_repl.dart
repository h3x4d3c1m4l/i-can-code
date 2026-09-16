// The web host is the only one that exists; everything else — the Dart VM a
// `flutter test` runs on included — falls through to the stub, which reports
// `isSupported == false` rather than throwing.
import 'package:i_can_code/services/python/python_repl_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/python/python_repl_web.dart' as impl;

/// Something the interpreter did that the terminal has to show.
sealed class ReplEvent {

  const ReplEvent();

}

/// Bytes the interpreter wrote, in the order it wrote them.
///
/// [fromStderr] is kept because the two streams are distinguishable at the
/// source and would be unrecoverable afterwards — not because the terminal
/// currently separates them. A real terminal interleaves both into one screen,
/// and so does this one.
class ReplOutput extends ReplEvent {

  final String text;
  final bool fromStderr;

  const ReplOutput(this.text, {required this.fromStderr});

}

/// The interpreter is up and CPython is about to print its banner.
class ReplStarted extends ReplEvent {

  const ReplStarted();

}

/// The session ended — `exit()`, or the end of input. Nothing more will arrive
/// from this [PythonRepl]; starting again means a new interpreter with none of
/// the old one's state.
class ReplExited extends ReplEvent {

  final int code;

  const ReplExited(this.code);

}

/// The harness itself failed: no runtime, a worker that would not start, a
/// missing asset. MUST NOT be phrased as a mistake the student made.
class ReplFailed extends ReplEvent {

  final String message;

  const ReplFailed(this.message);

}

/// One long-lived CPython sitting at an interactive prompt.
///
/// Distinct from [PythonRuntime] on purpose, and not a mode of it. That runs a
/// program and hands back what it printed; this one never finishes, holds the
/// names the student has defined, and is fed a line at a time. The two share
/// `python.wasm` and the WASI shim and nothing else.
///
/// Single-use. Once [ReplExited] arrives, the interpreter is gone — a new
/// session is a new [PythonRepl].
abstract class PythonRepl {

  /// False where this browser cannot host one. The screen stays reachable and
  /// explains itself rather than disappearing.
  ///
  /// It is not about the platform so much as the page: a blocking read needs
  /// `Atomics.wait` on a `SharedArrayBuffer`, which only exists on a
  /// cross-origin isolated page. See `web/coi-serviceworker.js`.
  bool get isSupported;

  /// Everything the interpreter produces. Broadcast, and closed on dispose.
  Stream<ReplEvent> get events;

  /// Boots the interpreter. Safe to call repeatedly; only the first does work.
  Future<void> start();

  /// Hands [text] to the interpreter's standard input, verbatim.
  ///
  /// The caller MUST include the newline that ends a line: this is a stream,
  /// not a line-based API, and CPython does not act until it sees one.
  void write(String text);

  /// Closes standard input — what Ctrl-D means. The interpreter exits.
  void endInput();

  /// True while the interpreter is parked waiting for a line, and so doing
  /// nothing else.
  ///
  /// Advisory, and can go stale between the read and the next statement. Used to
  /// tell a Ctrl-C that can simply clear what has been typed from one that has
  /// to stop a running program, where being wrong costs a needless restart
  /// rather than correctness.
  bool get isWaitingForInput;

  void dispose();

}

/// The REPL for this platform.
PythonRepl createPythonRepl() => impl.createPythonRepl();
