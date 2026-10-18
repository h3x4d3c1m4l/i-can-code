import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/services/vm/vm_image.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/components/vm/vm_session_view_model.dart';

/// The machine half of a screen that runs programs with windows: the
/// download, the runs, and everything they report.
///
/// It creates the runtime, and starts the download, as it is constructed: the
/// screen that holds it is the one thing that asks for the machine. [dispose]
/// frees the machine again.
///
/// The host keeps one machine per tab, so a session that opens while another
/// still stands takes the machine from it, and the other fails as
/// [VmFailure.replaced]. The newest session still standing holds the machine:
/// when it is disposed, the one under it builds a new machine if its own was
/// taken, as Retry would.
class VmSessionController extends ScreenControllerBase<VmSessionViewModel> {

  /// How often output reaches the screen while a program prints. A print loop
  /// sends a batch every 16 ms, and laying the card out that often is page work
  /// the emulator, on the same thread, pays for.
  static const Duration outputInterval = Duration(milliseconds: 200);

  /// Every session not yet disposed, oldest first, which is the order their
  /// screens stand in: a screen is built before the one it replaces goes.
  static final List<VmSessionController> _standing = [];

  final VmRuntime Function() _createRuntime;
  final EditorSettings _settings;
  final bool _imageIncluded;

  /// Called the first time the run in flight reports a window that shows, and
  /// at most once per run.
  final VoidCallback? onWindowShown;

  /// Not final: Retry throws a failed machine away and builds another, so every
  /// use MUST read the field.
  VmRuntime _runtime;

  StreamSubscription<VmEvent>? _subscription;

  /// The run whose events this screen shows. Everything about another run, a
  /// superseded one above all, is dropped.
  int? _runId;

  /// [onWindowShown] has been called for the run in flight.
  bool _windowShown = false;

  final StringBuffer _pendingOutput = StringBuffer();
  Timer? _outputTimer;
  bool _disposed = false;

  /// [createRuntime], [settings] and [imageIncluded] are for tests; the session
  /// makes its own, and takes the last from the build ([vmImageIncluded]).
  VmSessionController({
    required super.viewModel,
    required super.contextAccessor,
    this.onWindowShown,
    VmRuntime Function()? createRuntime,
    EditorSettings? settings,
    this._imageIncluded = vmImageIncluded,
  }) : _createRuntime = createRuntime ?? createVmRuntime,
       _settings = settings ?? GetIt.I<EditorSettings>(),
       _runtime = (createRuntime ?? createVmRuntime)() {
    _standing.add(this);
    _start();
  }

  /// The screen's element and its wiring, for the display. Changes on Retry,
  /// which is why a view keys the display on it.
  VmDisplayBinding get display => _runtime.display;

  /// Starts the download at once. Opening the screen is the one thing that
  /// asks for the machine, so the 20 MB is paid only by a student who wants it.
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
        if (!_windowShown && windows.any((window) => window.mapped)) {
          _windowShown = true;
          onWindowShown?.call();
        }
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

  /// Runs what is in the editor, with the setup the student keeps in the
  /// editor settings beside it.
  ///
  /// Before the machine is ready the run waits for it, so Run pressed during
  /// the download starts the program the moment it can. A run in flight is
  /// superseded, never refused.
  void run() {
    if (_disposed || !viewModel.canRun) return;

    final source = viewModel.code.text;

    // Before the new run exists, so nothing of the old one lands after it.
    _runId = null;
    _windowShown = false;
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

  /// Frees the machine. Parking does not give its memory back, and the app with
  /// a parked machine is a 500 MiB renderer, so leaving the screen is what does.
  ///
  /// Then hands the machine back to the newest session still standing, which is
  /// the one under this one when this one held it.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _standing.remove(this);
    _outputTimer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    _runtime.dispose();
    super.dispose();
    // After this machine is freed, so the new one takes nothing from anyone.
    _standing.lastOrNull?._takeBack();
  }

  /// Builds a new machine if this session's own was taken by a session that has
  /// left since. A failure of any other kind keeps its card and its Retry.
  void _takeBack() {
    if (viewModel.machine == TkinterMachine.failed && viewModel.failure == VmFailure.replaced) retry();
  }

}
