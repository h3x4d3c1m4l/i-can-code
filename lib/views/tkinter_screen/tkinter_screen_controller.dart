import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/vm/vm_image.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view_model.dart';

class TkinterScreenController extends ScreenControllerBase<TkinterScreenViewModel> {

  /// How often output reaches the screen while a program prints. A print loop
  /// sends a batch every 16 ms, and laying the card out that often is page work
  /// the emulator, on the same thread, pays for.
  static const Duration outputInterval = Duration(milliseconds: 200);

  final VmRuntime Function() _createRuntime;
  final CodeDraftStore _drafts;
  final EditorSettings _settings;
  final bool _imageIncluded;

  /// Not final: Retry throws a failed machine away and builds another, so every
  /// use MUST read the field.
  VmRuntime _runtime;

  StreamSubscription<VmEvent>? _subscription;

  /// The run whose events this screen shows. Everything about another run, a
  /// superseded one above all, is dropped.
  int? _runId;

  final StringBuffer _pendingOutput = StringBuffer();
  Timer? _outputTimer;
  bool _disposed = false;

  /// Writes the draft out when the app is hidden. That is also the last moment
  /// before ChromeOS discards a tab this heavy, which reloads it empty.
  late final AppLifecycleListener _lifecycle;

  /// [createRuntime], [drafts], [settings] and [imageIncluded] are for tests;
  /// the page makes its own, and takes the last from the build
  /// ([vmImageIncluded]).
  TkinterScreenController({
    required super.viewModel,
    required super.contextAccessor,
    VmRuntime Function()? createRuntime,
    CodeDraftStore? drafts,
    EditorSettings? settings,
    this._imageIncluded = vmImageIncluded,
  }) : _createRuntime = createRuntime ?? createVmRuntime,
       _drafts = drafts ?? GetIt.I<CodeDraftStore>(),
       _settings = settings ?? GetIt.I<EditorSettings>(),
       _runtime = (createRuntime ?? createVmRuntime)() {
    final draft = _drafts.pageCodeFor(_draftPage);
    if (draft != null) viewModel.code.text = draft;
    viewModel.code.addListener(_keepDraft);
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(_drafts.flush()));
    _start();
  }

  /// The screen's element and its wiring, for the display. Changes on Retry,
  /// which is why the view keys the display on it.
  VmDisplayBinding get display => _runtime.display;

  String get _draftPage => 'tkinter.${viewModel.subject}';

  /// Starts the download at once. Opening this page is the one thing that asks
  /// for the machine, so the 20 MB is paid only by a student who wants it.
  void _start() {
    // Before the browser question: a download from a build without the image
    // can only fail, and the page would blame the student's connection.
    if (!_imageIncluded) {
      viewModel.setNotIncluded();
      return;
    }
    if (!_runtime.isSupported) {
      viewModel.setUnavailable();
      return;
    }
    _subscription = _runtime.events.listen(_onEvent);
    unawaited(_runtime.load());
  }

  void _onEvent(VmEvent event) {
    if (_disposed) return;

    switch (event) {
      case VmLoadProgress():
        viewModel.setProgress(event);
      case VmReady(:final python, :final tk):
        viewModel.setReady(python: python, tk: tk);
      case VmFailed(:final failure, :final message):
        _flushOutput();
        viewModel.setFailed(failure, message);
      case VmOutput(:final runId, :final text) when runId == _runId:
        _pendingOutput.write(text);
        _outputTimer ??= Timer(outputInterval, _flushOutput);
      case VmWindows(:final runId, :final windows) when runId == _runId:
        viewModel.setWindows(windows);
      case VmRunHint(:final runId, :final hint) when runId == _runId:
        viewModel.addHint(hint);
      case VmRunEnded(:final runId, :final exit) when runId == _runId:
        _runId = null;
        _flushOutput();
        viewModel.finishRun(exit);
      case VmRunStarted() || VmOutput() || VmWindows() || VmRunHint() || VmRunEnded():
        break;
    }
  }

  void _flushOutput() {
    _outputTimer?.cancel();
    _outputTimer = null;
    if (_pendingOutput.isEmpty) return;
    viewModel.appendOutput(_pendingOutput.toString());
    _pendingOutput.clear();
  }

  /// Runs what is in the editor.
  ///
  /// Before the machine is ready the run waits for it, so Run pressed during
  /// the download starts the program the moment it can. A run in flight is
  /// superseded, never refused.
  void run() {
    if (_disposed || !viewModel.canRun) return;

    final source = viewModel.code.text;
    unawaited(_drafts.flush());

    // Before the new run exists, so nothing of the old one lands after it.
    _runId = null;
    _outputTimer?.cancel();
    _outputTimer = null;
    _pendingOutput.clear();
    viewModel.startRun();

    _runId = _runtime.run(VmProgram.source(source, setup: _settings.tkinterSetup)).id;
  }

  /// Ends the run in flight. The button turns back at once; the machine parks
  /// behind it, and what the program printed stays on screen. A stop is not a
  /// verdict and gets no notice.
  Future<void> stop() async {
    if (!viewModel.running) return;
    viewModel.stopRun();
    await _runtime.stop();
  }

  /// The close button on a window's own strip: that window's close path, as a
  /// window manager would do it. The cross on the dialog itself is [stop],
  /// which ends the program rather than asking a window to close.
  void closeWindowById(int xid) => _runtime.closeWindow(xid);

  /// Throws the failed machine away and builds another. A failure after the
  /// machine was ready stays failed for good, so a new one is the only retry
  /// that always works; the download itself comes out of the browser's cache.
  void retry() {
    if (_disposed) return;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _runtime.dispose();
    _runId = null;
    _runtime = _createRuntime();
    viewModel.resetMachine();
    _start();
  }

  void onDisplayFocusChange(bool focused) => viewModel.setDisplayFocused(focused);

  /// The sample is not a draft, so going back to it forgets the one there was.
  void _keepDraft() {
    final code = viewModel.code.text;
    if (code == TkinterScreenViewModelBase.sample) {
      _drafts.forgetPage(_draftPage);
    } else {
      _drafts.keepPage(_draftPage, code);
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

  /// Frees the machine. Parking does not give its memory back, and the app with
  /// a parked machine is a 500 MiB renderer, so leaving the page is what does.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    viewModel.code.removeListener(_keepDraft);
    // Whatever was typed since the last pause, before the editor goes.
    unawaited(_drafts.flush());
    _lifecycle.dispose();
    _outputTimer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    _runtime.dispose();
    super.dispose();
  }

}
