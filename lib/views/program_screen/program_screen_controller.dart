import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/python/python_repl.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/services/terminal/line_editor.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/program_screen/program_screen_view_model.dart';

/// Starts the interpreter that runs [program].
typedef ProgramSessionFactory = PythonRepl Function({String? program});

class ProgramScreenController extends ScreenControllerBase<ProgramScreenViewModel> {

  final ProgramSessionFactory _createSession;
  final CodeDraftStore _drafts;
  final PythonRuntime _runtime;

  /// The run in flight, or null between runs. A run is a new interpreter, so a
  /// program never finds the names the one before it defined.
  PythonRepl? _session;
  StreamSubscription<ReplEvent>? _subscription;

  /// The line discipline for the run in flight, which CPython does not do
  /// itself (see [LineEditor]). Null between runs, so what is typed then goes
  /// nowhere.
  LineEditor? _editor;

  /// What the program has written on the line the cursor is on, which is where
  /// an `input()` prompt sits. Read off the screen, as the console does.
  String _prompt = '';

  bool _disposed = false;

  /// Writes the draft out when the app is hidden, which is the last moment
  /// before a closed or reloaded tab takes the pending write with it.
  late final AppLifecycleListener _lifecycle;

  /// [createSession], [drafts] and [runtime] are for tests; the page makes or
  /// finds its own.
  ProgramScreenController({
    required super.viewModel,
    required super.contextAccessor,
    ProgramSessionFactory? createSession,
    CodeDraftStore? drafts,
    PythonRuntime? runtime,
  }) : _createSession = createSession ?? createPythonRepl,
       _drafts = drafts ?? GetIt.I<CodeDraftStore>(),
       _runtime = runtime ?? GetIt.I<PythonRuntime>() {
    final draft = _drafts.pageCodeFor(viewModel.draftPage);
    if (draft != null) viewModel.code.text = draft;
    viewModel.code.addListener(_keepDraft);
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(_drafts.flush()));

    viewModel.terminal.onOutput = (data) => _editor?.write(data);

    // Constructing one starts nothing: only `start` reaches for a worker.
    final probe = _createSession();
    final supported = probe.isSupported;
    probe.dispose();
    if (!supported) {
      viewModel.setStatus(ProgramStatus.unavailable);
      return;
    }

    _warmRuntime();
  }

  /// Compiles the interpreter while the student writes, and asks it its name.
  ///
  /// The lesson runtime and this page share one compiled module
  /// (`loadPythonBuild`), so warming that one is what keeps the first Run from
  /// waiting on 7 MB of CPython.
  void _warmRuntime() {
    unawaited(
      _runtime.ready().then((_) {
        if (!_disposed) viewModel.setRuntimeVersion(_runtime.version);
      }).catchError((_) {}),
    );
  }

  /// Runs what is in the editor on an empty terminal, ending a run that is
  /// still going.
  void run() {
    if (_disposed || viewModel.status == ProgramStatus.unavailable) return;
    unawaited(_drafts.flush());
    _end();

    // Erase the screen, then the scrollback, then go home: every run starts on
    // an empty terminal, as a new run in an IDE does.
    viewModel.terminal.write('\x1b[2J\x1b[3J\x1b[H');
    _prompt = '';

    final session = _createSession(program: viewModel.code.text);
    _session = session;
    _editor = LineEditor(
      echo: viewModel.terminal.write,
      submit: (line) {
        _prompt = '';
        session.write(line);
      },
      endOfInput: session.endInput,
      prompt: () => _prompt,
      // wasm has no signals, so this cannot raise a KeyboardInterrupt. Ending
      // the run is what Ctrl-C in `input()` comes to anyway.
      interrupt: stop,
      canDiscardLine: () => false,
    );
    _subscription = session.events.listen((event) => _onEvent(session, event));

    viewModel.setStatus(ProgramStatus.starting);
    unawaited(session.start());
  }

  /// Ends the run in flight, and says so.
  void stop() {
    if (_disposed || _session == null) return;
    _end();
    viewModel.setStatus(ProgramStatus.idle);
    _notice(localizations.programScreen_stopped);
  }

  void _onEvent(PythonRepl session, ReplEvent event) {
    // A run that was ended can still have events on their way.
    if (_disposed || !identical(session, _session)) return;

    switch (event) {
      case ReplStarted():
        viewModel.setStatus(ProgramStatus.running);
      case ReplOutput(:final text):
        _write(text);
      case ReplExited(:final code):
        _end();
        viewModel.setStatus(ProgramStatus.idle);
        _notice(localizations.programScreen_finished(code));
      case ReplFailed(:final message):
        _end();
        viewModel.setStatus(ProgramStatus.idle);
        _notice(localizations.programScreen_failed);
        // The host's own words, for whoever helps the student. Untranslated.
        _write('\x1b[90m$message\x1b[0m\n');
    }
  }

  /// Throws the run in flight away. The worker is terminated rather than asked,
  /// because it is parked in a read or busy in the program and hears nothing.
  void _end() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _session?.dispose();
    _session = null;
    _editor = null;
  }

  /// Puts program output on the screen. Releasing the anchor first is not
  /// optional, for the reason [LineEditor.releaseAnchor] gives.
  void _write(String text) {
    _editor?.releaseAnchor();
    viewModel.terminal.write(cookOutput(text));

    final lineStart = text.lastIndexOf(_lineBreak) + 1;
    final line = lineStart == 0 ? _prompt + text : text.substring(lineStart);
    // A program printing without newlines would grow this without end.
    _prompt = line.length > _maxPromptLength ? line.substring(line.length - _maxPromptLength) : line;
  }

  static final RegExp _lineBreak = RegExp('[\r\n]');

  static const int _maxPromptLength = 256;

  /// A line from the app rather than from the program, in grey so it cannot be
  /// mistaken for something the program printed, after one blank line.
  void _notice(String message) {
    // `print` writes its newline separately, so a stop can land between the
    // two and leave the cursor at the end of a line.
    final endLine = _prompt.isEmpty ? '' : '\n';
    _write('$endLine\n\x1b[90m— $message —\x1b[0m\n');
  }

  /// The sample is not a draft, so going back to it forgets the one there was.
  void _keepDraft() {
    final code = viewModel.code.text;
    if (code == ProgramScreenViewModelBase.sample) {
      _drafts.forgetPage(viewModel.draftPage);
    } else {
      _drafts.keepPage(viewModel.draftPage, code);
    }
  }

  /// Back to the subject picker, which is the app's home.
  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const SubjectsRoute()]);
  }

  /// The catalog this page belongs to.
  Future<void> goToCatalog() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([
      const SubjectsRoute(),
      CatalogRoute(subjectSlug: subjectSlug(viewModel.subject)),
    ]);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _end();
    viewModel.code.removeListener(_keepDraft);
    // Whatever was typed since the last pause, before the editor goes.
    unawaited(_drafts.flush());
    _lifecycle.dispose();
    super.dispose();
  }

}
