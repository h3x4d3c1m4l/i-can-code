import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/microbit/microbit_link.dart';
import 'package:i_can_code/services/terminal/line_editor.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';

/// The board half of both micro:bit screens: permission, the session's events,
/// and the terminal they land on.
///
/// One class for two screens because they differ in what they offer rather than
/// in how they talk to a board. [interrupt] is that difference: a REPL wants the
/// prompt, a program wants to run.
class MicrobitSessionController extends ScreenControllerBase<MicrobitSessionViewModel> {

  /// What MicroPython prints when its REPL starts. Everything a restart printed
  /// before this is the interrupt that got there, not the board's own output.
  static const String _bannerMarker = 'MicroPython v';

  /// How many chunks after a restart may be searched for [_bannerMarker].
  static const int _bannerChunks = 20;

  final MicrobitLink _link = createMicrobitLink();

  StreamSubscription<MicrobitEvent>? _subscription;
  bool _disposed = false;

  /// How many more chunks may be searched for the banner after a restart.
  ///
  /// Bounded so a board that never sends one cannot leave the screen clearing
  /// itself much later, when the reader soft-reboots by hand. A restart's own
  /// output is one or two chunks.
  int _bannerBudget = 0;

  /// The tail of the last chunk, kept only while looking for the banner, in case
  /// the marker falls across two reads.
  String _tail = '';

  /// Whether to break into MicroPython's prompt every time the board starts.
  ///
  /// True on a REPL, where the prompt is the point. False where the board's own
  /// program is: a Ctrl-C would stop it a moment after it started.
  final bool interrupt;

  MicrobitSessionController({required super.viewModel, required super.contextAccessor, required this.interrupt}) {
    // No line discipline in between: MicroPython echoes, edits and keeps
    // history itself, so the console's would double every character. Ctrl-C
    // rides along and raises a real `KeyboardInterrupt`.
    viewModel.terminal.onOutput = _link.write;

    unawaited(_start());
  }

  /// Settles what this browser can do, and picks up a board permitted in an
  /// earlier visit. The permission outlives the page.
  Future<void> _start() async {

    // Before anything is asked of the link, so a failure on the way up is seen
    // rather than arriving before anyone is listening.
    _subscription = _link.events.listen(_onEvent);

    if (!_link.isSupported || !await _link.transportAvailable()) {
      // "This browser cannot" is only true when nothing else has spoken: a core
      // that would not load has already said so, in its own words.
      if (!_disposed && viewModel.status != MicrobitStatus.failed) {
        viewModel.setStatus(MicrobitStatus.unavailable);
      }
      return;
    }

    final devices = await _link.listDevices();
    if (_disposed) return;

    viewModel.setDevices(devices);
    if (devices.isNotEmpty) await _open();
  }

  /// Opens the browser's own device picker.
  ///
  /// MUST be reached straight from a button press: WebUSB refuses a
  /// `requestDevice()` that is not inside a user gesture, and an `await` before
  /// it is enough to lose that gesture. So nothing is awaited here first.
  Future<void> connect() async {

    viewModel.setStatus(MicrobitStatus.connecting);

    await _link.requestAccess();
    if (_disposed) return;

    // What matters is what is permitted now. A reader who cancelled the picker
    // may still have granted access earlier.
    final devices = await _link.listDevices();
    if (_disposed) return;

    viewModel.setDevices(devices);

    if (devices.isEmpty) {
      viewModel.setStatus(MicrobitStatus.noDevice);
      return;
    }

    await _open();
  }

  /// Hands the board to the session, which holds it from here on.
  Future<void> _open() async {
    viewModel.setStatus(MicrobitStatus.connecting);
    await _link.connect(interrupt: interrupt);
  }

  void _onEvent(MicrobitEvent event) {
    if (_disposed) return;

    switch (event) {
      case MicrobitConnected(:final info):
        // Also cleared here, not only on disconnect: a connect that follows a
        // failure never saw a disconnect.
        _clearTerminal();
        _expectBanner();
        viewModel.setConnected(info);
      case MicrobitOutput(:final text):
        _write(text);
      case MicrobitFlashPlan(:final changed, :final total):
        viewModel.setFlashPlan(changed, total);
      case MicrobitFlashPlanUnknown(:final message):
        viewModel.setFlashPlanUnknown(message);
      case MicrobitFlashProgress(:final fraction):
        viewModel.setFlashing(fraction);
      case MicrobitFlashed():
        // The board reboots into the new program, so what the old one printed
        // belongs to something that no longer exists.
        _clearTerminal();
        _expectBanner();
        viewModel.setFlashed();
      case MicrobitDisconnected():
        // Nothing on the terminal belongs to anything any more: the interpreter
        // that printed it is gone, and a reconnect resets the board.
        _clearTerminal();
        viewModel.setDisconnected();
      case MicrobitFailed(:final failure, :final message):
        viewModel.setFailure(failure, message);
    }
  }

  void _clearTerminal() {
    viewModel.terminal.buffer.clear();
    viewModel.terminal.setCursor(0, 0);
  }

  /// Writes what is in the editor to the board.
  Future<void> flash() async {
    // The last flash's plan was about a program that has already been written.
    viewModel
      ..clearFlashPlan()
      ..setFlashing(0);
    await _link.flash(viewModel.code.text);
  }

  /// Starts the board over with a hard reset, which also prints the boot banner
  /// that tells the reader something is listening.
  Future<void> restart() async {
    _clearTerminal();
    _expectBanner();
    await _link.restart(interrupt: interrupt);
  }

  /// Puts board output on the terminal.
  ///
  /// No tty driver translates `\n` into `\r\n` here, so without [cookOutput]
  /// every line starts under the end of the one before it.
  ///
  /// While a restart's banner is expected, the screen is cleared the moment it
  /// arrives, which drops the traceback the interrupt printed on the way. The
  /// output is written either way, so a banner that never comes hides nothing.
  void _write(String text) {

    if (_bannerBudget > 0) {
      _bannerBudget -= 1;
      _tail += text;

      final at = _tail.indexOf(_bannerMarker);
      if (at >= 0) {
        final banner = _tail.substring(at);
        _bannerBudget = 0;
        _tail = '';
        _clearTerminal();
        viewModel.terminal.write(cookOutput(banner));
        return;
      }

      // Enough to catch a marker split across two reads, and no more.
      if (_tail.length > _bannerMarker.length) {
        _tail = _tail.substring(_tail.length - _bannerMarker.length);
      }
    }

    viewModel.terminal.write(cookOutput(text));
  }

  /// Watches for the banner, if one is coming at all.
  ///
  /// Only an interrupted start prints one: MicroPython says nothing on its way
  /// into a program, so a screen that lets the program run would spend this
  /// budget on the program's own output.
  void _expectBanner() {
    _bannerBudget = interrupt ? _bannerChunks : 0;
    _tail = '';
  }

  /// Back to the language picker, which is the app's home.
  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const LanguagesRoute()]);
  }

  /// The catalog this board belongs to.
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
    // Lets the board go, so leaving this screen does not lock another tab out.
    _link.dispose();
    super.dispose();
  }

}
