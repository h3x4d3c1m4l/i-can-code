import 'dart:async';
import 'dart:typed_data';

import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/folder_store.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/python/python_repl.dart';
import 'package:i_can_code/services/terminal/line_editor.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/repl_screen/repl_screen_view_model.dart';

class ReplScreenController extends ScreenControllerBase<ReplScreenViewModel> {

  /// Not final: stopping a session means throwing the interpreter away and
  /// building another, so every use MUST read the field rather than hold a
  /// tear-off, which would keep calling the dead one.
  late PythonRepl _repl = _createRepl();

  late final LineEditor _editor;

  StreamSubscription<ReplEvent>? _subscription;
  bool _disposed = false;

  /// What the interpreter has written on the line the cursor is on: `>>> `,
  /// `... `, the prompt of an `input()`, or the end of a `print` without a
  /// newline. Empty once a line has been submitted, until it writes again.
  ///
  /// Read off the screen, which is where a terminal has always got it. The
  /// worker flushes whatever is pending just before it parks, so the last thing
  /// written before a read is the prompt that read is for.
  String _prompt = '';

  /// The interpreter is part way through a block — `for ...:` typed, the body
  /// still to come. Throwing away the current line leaves the block open, and
  /// nothing a line discipline can send will close it.
  bool get _inPendingBlock => _prompt.endsWith('... ');

  ReplScreenController({required super.viewModel, required super.contextAccessor}) {
    _editor = LineEditor(
      echo: viewModel.terminal.write,
      submit: (line) {
        _prompt = '';
        _repl.write(line);
      },
      endOfInput: () => _repl.endInput(),
      prompt: () => _prompt,
      // wasm has no signals, so nothing can interrupt a running program from
      // inside it — and an open block cannot be closed from outside. Ctrl-C is
      // therefore the Restart button in both cases, which at least always ends
      // what is going on.
      interrupt: () => unawaited(restart(interrupted: true)),
      canDiscardLine: () => _repl.isWaitingForInput && !_inPendingBlock,
    );

    // Everything typed into the terminal goes to the line discipline, never
    // straight to Python: the basic REPL does no echo and no editing.
    viewModel.terminal.onOutput = _editor.write;

    unawaited(_start());
  }

  /// A new interpreter, which starts with the folder as it is now.
  PythonRepl _createRepl() => createPythonRepl(files: viewModel.files);

  Future<void> _start() async {
    if (!_repl.isSupported) {
      viewModel.setStatus(ReplStatus.unavailable);
      return;
    }
    _subscription = _repl.events.listen(_onEvent);
    await _repl.start();
  }

  void _onEvent(ReplEvent event) {
    if (_disposed) return;

    switch (event) {
      case ReplStarted():
        viewModel.setStatus(ReplStatus.running);
      case ReplOutput(:final text):
        _write(text);
      case ReplFiles(:final changed, :final removed):
        viewModel.folder.apply(viewModel.subject, changed: changed, removed: removed);
      case ReplExited(:final code):
        viewModel.setStatus(ReplStatus.exited);
        _notice(localizations.replScreen_exited(code));
      case ReplFailed(:final message):
        viewModel.setFailure(message);
        _notice(localizations.replScreen_failed);
    }
  }

  /// Puts interpreter output on the screen.
  ///
  /// Releasing the anchor first is not optional: writing moves the cursor, and
  /// the line editor's saved position would otherwise send the next keystroke's
  /// repaint over the top of this output.
  void _write(String text) {
    _editor.releaseAnchor();
    viewModel.terminal.write(cookOutput(text));

    final lineStart = text.lastIndexOf(_lineBreak) + 1;
    final line = lineStart == 0 ? _prompt + text : text.substring(lineStart);
    // A program printing without newlines would grow this without end.
    _prompt = line.length > _maxPromptLength ? line.substring(line.length - _maxPromptLength) : line;
  }

  static final RegExp _lineBreak = RegExp('[\r\n]');

  static const int _maxPromptLength = 256;

  /// A line from the app rather than from Python, marked as such. Grey, so it
  /// cannot be mistaken for something the interpreter said.
  void _notice(String message) {
    _write('\n\x1b[90m— $message —\x1b[0m\n');
  }

  /// Throws the interpreter away and starts another.
  ///
  /// The terminal keeps its scrollback: what was printed still happened, and a
  /// student who was in the middle of something wants to see it. What does not
  /// survive is every name they had defined, which is why [interrupted] says so
  /// out loud.
  Future<void> restart({bool interrupted = false}) async {
    await _subscription?.cancel();
    _subscription = null;
    _repl.dispose();
    _repl = _createRepl();
    _prompt = '';

    if (interrupted) _notice(localizations.replScreen_stopped);
    viewModel.setStatus(ReplStatus.starting);
    await _start();
  }

  /// Why [name] cannot be given to a file the student types, or null.
  FolderNameProblem? folderNameProblem(String name, {String? current}) =>
      viewModel.folder.problemWith(viewModel.subject, name, current: current);

  /// Keeps a file the student typed or changed, in the folder and in the
  /// interpreter, which works on a copy of it. [replacing] is the name the file
  /// had, which goes when it differs.
  void saveFile({required String name, required Uint8List bytes, String? replacing}) {
    if (_disposed) return;
    if (replacing != null && replacing != name) deleteFile(replacing);
    viewModel.folder.put(viewModel.subject, name, bytes);
    _repl.putFile(name, bytes);
  }

  /// Takes [path] out of the folder, and out of the interpreter.
  void deleteFile(String path) {
    if (_disposed) return;
    viewModel.folder.remove(viewModel.subject, path);
    _repl.removeFile(path);
  }

  /// Back to the subject picker, which is the app's home.
  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const SubjectsRoute()]);
  }

  /// The catalog this console belongs to.
  Future<void> goToCatalog() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([
      const SubjectsRoute(),
      CatalogRoute(subjectSlug: subjectSlug(viewModel.subject)),
    ]);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _repl.dispose();
    super.dispose();
  }

}
