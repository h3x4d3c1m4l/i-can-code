import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/python/python_repl.dart';
import 'package:i_can_code/services/terminal/line_editor.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/repl_screen/repl_screen_view_model.dart';

class ReplScreenController extends ScreenControllerBase<ReplScreenViewModel> {

  /// Not final: stopping a session means throwing the interpreter away and
  /// building another, so every use MUST read the field rather than hold a
  /// tear-off, which would keep calling the dead one.
  PythonRepl _repl = createPythonRepl();

  late final LineEditor _editor;

  StreamSubscription<ReplEvent>? _subscription;
  bool _disposed = false;

  /// The prompt the interpreter printed most recently.
  ///
  /// Read off the screen, which is where a terminal has always got it. The
  /// worker flushes whatever is pending just before it parks, so the last thing
  /// written before a read is the prompt that read is for.
  String _prompt = '';

  /// A prompt sits at the very end of what was written, and there are only two
  /// of them.
  static final RegExp _promptAtEnd = RegExp(r'(>>> |\.\.\. )$');

  /// The interpreter is part way through a block — `for ...:` typed, the body
  /// still to come. Throwing away the current line leaves the block open, and
  /// nothing a line discipline can send will close it.
  bool get _inPendingBlock => _prompt == '... ';

  ReplScreenController({required super.viewModel, required super.contextAccessor}) {
    _editor = LineEditor(
      echo: viewModel.terminal.write,
      submit: (line) => _repl.write(line),
      endOfInput: () => _repl.endInput(),
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

    final prompt = _promptAtEnd.firstMatch(text);
    if (prompt != null) _prompt = prompt.group(0)!;
  }

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
    _repl = createPythonRepl();
    _prompt = '';

    if (interrupted) _notice(localizations.replScreen_stopped);
    viewModel.setStatus(ReplStatus.starting);
    await _start();
  }

  /// Back to the language picker, which is the app's home.
  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const LanguagesRoute()]);
  }

  /// The catalog this console belongs to.
  Future<void> goToCatalog() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([
      const LanguagesRoute(),
      CatalogRoute(languageSlug: languageSlug(viewModel.language)),
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
