// The web host is the only one that exists; everything else — the Dart VM a
// `flutter test` runs on included — falls through to the stub, which reports
// `isSupported == false` rather than throwing.
import 'dart:typed_data';

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

/// The interpreter is up. At a prompt CPython is about to print its banner; a
/// program is about to start.
class ReplStarted extends ReplEvent {

  const ReplStarted();

}

/// The session ended — `exit()`, the end of input, or the end of the program.
/// Nothing more will arrive
/// from this [PythonRepl]; starting again means a new interpreter with none of
/// the old one's state.
class ReplExited extends ReplEvent {

  final int code;

  const ReplExited(this.code);

}

/// What the interpreter did to its folder since it last said: the files it
/// wrote or changed, by path relative to its root, and the paths it removed.
///
/// Only what the program did. A file handed over with [PythonRepl.putFile] does
/// not come back, unless it could not be written, and then it comes back as it
/// really is.
class ReplFiles extends ReplEvent {

  final Map<String, Uint8List> changed;
  final List<String> removed;

  const ReplFiles({required this.changed, required this.removed});

}

/// The harness itself failed: no runtime, a worker that would not start, a
/// missing asset. MUST NOT be phrased as a mistake the student made.
class ReplFailed extends ReplEvent {

  final String message;

  const ReplFailed(this.message);

}

/// One long-lived CPython on a terminal: sitting at an interactive prompt, or
/// running one program whose standard input is the terminal.
///
/// Distinct from [PythonRuntime] on purpose, and not a mode of it. That runs a
/// program and hands back what it printed once it is done; this one shows
/// output as it is written and is fed a line at a time while it runs. The two
/// share `python.wasm` and the WASI shim and nothing else.
///
/// Single-use. Once [ReplExited] arrives, the interpreter is gone — a new
/// session is a new [PythonRepl].
abstract class PythonRepl {

  /// The largest file [putFile] takes. `file_channel.js` MUST have room for one
  /// of these and its path.
  static const int maxPutBytes = 1024 * 1024;

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
  /// not a line-based API, and CPython does not act until it sees one. [text]
  /// MUST NOT hold U+0004, which is how [endInput] travels.
  void write(String text);

  /// Ends standard input for one read, as Ctrl-D on an empty line does in a
  /// terminal. At a prompt the interpreter exits. Inside `input()` that read
  /// raises EOFError, and the session goes on.
  void endInput();

  /// Writes [bytes] to [path] in the interpreter's folder, in place of what is
  /// there. [path] is relative to its root, the program's working directory.
  ///
  /// Lands the next time the interpreter asks for input: at a prompt at once,
  /// while a program is busy at its next `input()`. Before [start] it is part
  /// of the folder the interpreter starts with.
  ///
  /// [bytes] MUST NOT be longer than [maxPutBytes].
  void putFile(String path, Uint8List bytes);

  /// Takes the file at [path] away, as [putFile] puts one there.
  void removeFile(String path);

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
///
/// Given a [program], it runs that as `/main.py` instead of starting a prompt,
/// and exits when the program does. `input()` then waits for a line written
/// with [PythonRepl.write], as it would in a terminal.
///
/// [files] is the folder it starts with, by path relative to its root.
PythonRepl createPythonRepl({String? program, Map<String, Uint8List> files = const {}}) =>
    impl.createPythonRepl(program: program, files: files);
