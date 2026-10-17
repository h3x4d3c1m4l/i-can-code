import 'dart:ui' show Offset, Rect, Size;

import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';
import 'package:re_editor/re_editor.dart';

part 'tkinter_screen_view_model.g.dart';

/// Where the machine is, as the screen has to show it.
enum TkinterMachine {

  /// Downloading, or restoring once it has. A run asked for now waits.
  loading,

  /// Parked and waiting for a program, or running one.
  ready,

  /// It cannot run programs. `failure` says why; Retry builds a new one.
  failed,

  /// This browser cannot host it at all.
  unavailable,

  /// This build ships without the machine's image. Neither the browser nor the
  /// connection is to blame, and there is nothing to download.
  notIncluded,

}

/// A sentence about how the last run ended. Never a verdict: nothing on this
/// page is checked, and a stop gets none of these.
enum TkinterNotice {

  /// A Tk root and no `mainloop()`, so the window closed at once.
  noMainloop,

  /// The program read standard input, which the machine does not offer.
  noInput,

  /// It ended with an error, whose traceback is in the output.
  crashed,

  outOfMemory,

  /// A window or canvas larger than the X server may allocate. A limit of the
  /// machine: the same program runs on an ordinary computer.
  tooLarge,

  /// The machine failed and the program did not.
  harnessBroken,
  harnessFetch,
  harnessUnresponsive;

  /// False for a notice that MUST NOT read as the student's mistake.
  bool get aboutTheProgram => switch (this) {
    noMainloop || noInput || crashed || outOfMemory => true,
    tooLarge || harnessBroken || harnessFetch || harnessUnresponsive => false,
  };

}

/// The part of [screen] the program shows itself on: the smallest rectangle
/// around every mapped window in [windows], each clipped to the screen first.
/// Null when none shows any of itself.
///
/// A dialog widens it to hold the window under it as well, so both stay in
/// view. A window partly off the screen counts only for the part on it: the
/// rest was never drawn.
Rect? windowRegion(Iterable<VmWindow> windows, {Size screen = vmScreenSize}) {
  final bounds = Offset.zero & screen;
  Rect? region;
  for (final window in windows) {
    if (!window.mapped) continue;
    final shown = Rect.fromLTWH(
      window.x.toDouble(),
      window.y.toDouble(),
      window.width.toDouble(),
      window.height.toDouble(),
    ).intersect(bounds);
    if (shown.isEmpty) continue;
    region = region?.expandToInclude(shown) ?? shown;
  }
  return region;
}

class TkinterScreenViewModel = TkinterScreenViewModelBase with _$TkinterScreenViewModel;

abstract class TkinterScreenViewModelBase extends ScreenViewModelBase with Store {

  /// What the editor holds the first time: a window with a label and a button
  /// that counts its clicks. Dutch, like the course it sits beside.
  static const String sample = '''
import tkinter as tk

klikken = 0


def klik():
    global klikken
    klikken = klikken + 1
    label.config(text=f"Je hebt {klikken} keer geklikt")


root = tk.Tk()
root.title("Mijn eerste venster")

label = tk.Label(root, text="Klik op de knop", padx=40, pady=20)
label.pack()

knop = tk.Button(root, text="Klik mij", command=klik)
knop.pack(pady=(0, 20))

root.mainloop()
''';

  /// How much of the output the card shows: the end of it. The host forwards
  /// up to 256 KiB, and laying all of that out again on every batch is exactly
  /// the page work the emulator cannot share its thread with.
  static const int outputShown = 20000;

  /// What Python prints when `input()` finds standard input closed, which is
  /// what the machine gives every program.
  static const String _eofError = 'EOFError: EOF when reading a line';

  /// Xlib's report of a request the X server had no memory for, which then
  /// ends the program. The guest lets Xorg's heap grow 16 MiB past its warm
  /// size, and Tk backs a Canvas with a pixmap the size of what it redraws, so
  /// 3000 × 3000 is past it.
  static final RegExp _xBadAlloc = RegExp(r'X Error of failed request:\s+BadAlloc');

  /// The subject this page belongs to. Empty when the address
  /// named something that is not a subject of ours.
  final String subject;

  /// Not observable, like every editor's controller: it notifies its own
  /// listeners, and a MobX observable over every keystroke would rebuild the
  /// screen on each one.
  final CodeLineEditingController code = CodeLineEditingController.fromText(sample);

  @readonly
  TkinterMachine _machine = TkinterMachine.loading;

  /// How far the machine's load is. Null before the first report, while the
  /// manifest that names the total is still on its way.
  @readonly
  VmLoadProgress? _loadProgress;

  /// Why the machine failed, for [TkinterMachine.failed].
  @readonly
  VmFailure? _failure;

  /// The harness's own words, in English, for whoever helps the student. The
  /// page folds them away rather than show them as its own.
  @readonly
  String? _failureMessage;

  /// What the guest's interpreter and Tk call themselves, once ready.
  @readonly
  String? _python;

  @readonly
  String? _tk;

  /// A run has been asked for and has not ended for the student. It stays true
  /// while the run waits for the machine to be ready.
  @readonly
  bool _running = false;

  /// The run's top-level windows, bottom to top.
  @readonly
  List<VmWindow> _windows = const [];

  /// Everything the program printed, stdout and stderr in the order they came.
  @readonly
  String _output = '';

  @readonly
  Set<VmHint> _hints = const {};

  /// How the last run ended. Null while one runs, and before the first.
  @readonly
  VmExit? _exit;

  /// The program's screen holds the keyboard.
  @readonly
  bool _displayFocused = false;

  TkinterScreenViewModelBase({required super.contextAccessor, required String subjectSlug})
    : subject = subjectFromSlug(subjectSlug) ?? '';

  /// Whether Run does anything now. A machine still loading takes the run and
  /// starts it once ready.
  @computed
  bool get canRun => _machine == TkinterMachine.loading || _machine == TkinterMachine.ready;

  /// The window the frame is drawn for: the program's main window while it
  /// shows, else the topmost one that does. A program that withdraws its root
  /// to show only a dialog gets the dialog's title.
  @computed
  VmWindow? get framedWindow {
    for (final window in _windows) {
      if (window.isRoot && window.mapped) return window;
    }
    for (final window in _windows.reversed) {
      if (window.mapped) return window;
    }
    return null;
  }

  /// The windows the frame does not name, bottom to top: the ones the page
  /// gives a strip of their own. With no window manager a second `Toplevel`
  /// would otherwise carry no title and no way to close it.
  @computed
  List<VmWindow> get labelledWindows {
    final framed = framedWindow;
    return [
      for (final window in _windows)
        if (window.mapped && window.xid != framed?.xid) window,
    ];
  }

  /// The part of the guest's screen the page shows: see [windowRegion]. Null
  /// while no window shows.
  @computed
  Rect? get shownRegion => windowRegion(_windows);

  /// `Python 3.12.12 · Tk 8.6.16`, the machine naming itself. Null until it has.
  @computed
  String? get interpreterLabel => switch ((_python, _tk)) {
    (final String python, final String tk) => '$python · Tk $tk',
    (final String python, null) => python,
    _ => null,
  };

  /// The end of [output], at most [outputShown] characters of it.
  @computed
  String get visibleOutput => _output.length <= outputShown ? _output : _output.substring(_output.length - outputShown);

  /// Not everything the program printed is on screen: the host cut it off, or
  /// the card shows only its end.
  @computed
  bool get outputIncomplete => (_exit?.truncated ?? false) || _output.length > outputShown;

  /// What to say about the last run, in the order it should be read.
  @computed
  List<TkinterNotice> get notices {
    final exit = _exit;
    // The failure card already says it, and says more.
    if (exit == null || _machine == TkinterMachine.failed) return const [];

    return switch (exit.reason) {
      VmEndReason.stopped => const [],
      VmEndReason.broken => const [TkinterNotice.harnessBroken],
      VmEndReason.fetch => const [TkinterNotice.harnessFetch],
      VmEndReason.unresponsive => const [TkinterNotice.harnessUnresponsive],
      VmEndReason.outOfMemory => const [TkinterNotice.outOfMemory],
      VmEndReason.exit || VmEndReason.closed => [
        if (_hints.contains(VmHint.tkNoMainloop)) TkinterNotice.noMainloop,
        // The EOFError is the program's own traceback, and "you crashed" would
        // be less use than why.
        if (exit.failed && _output.contains(_eofError))
          TkinterNotice.noInput
        else if (exit.failed && _xBadAlloc.hasMatch(_output))
          TkinterNotice.tooLarge
        else if (exit.failed)
          TkinterNotice.crashed,
      ],
    };
  }

  /// Ignored unless the machine is loading. A byte count that trails a failure
  /// must not hide the failure card and its Retry: only [resetMachine] leaves
  /// [TkinterMachine.failed].
  @action
  void setProgress(VmLoadProgress progress) {
    if (_machine != TkinterMachine.loading) return;
    _loadProgress = progress;
  }

  @action
  void setReady({String? python, String? tk}) {
    _python = python;
    _tk = tk;
    _failure = null;
    _failureMessage = null;
    _machine = TkinterMachine.ready;
  }

  /// Forgets how the last run ended too: a run the failing machine ended says
  /// nothing about the program, and its notice would come back after Retry.
  @action
  void setFailed(VmFailure failure, String message) {
    _failure = failure;
    _failureMessage = message;
    _running = false;
    _windows = const [];
    _exit = null;
    _hints = const {};
    _machine = TkinterMachine.failed;
  }

  @action
  void setUnavailable() => _machine = TkinterMachine.unavailable;

  @action
  void setNotIncluded() => _machine = TkinterMachine.notIncluded;

  /// A new machine is on its way, after a retry. Nothing said about a run on
  /// the old one may come back on it.
  @action
  void resetMachine() {
    _loadProgress = null;
    _failure = null;
    _failureMessage = null;
    _running = false;
    _windows = const [];
    _exit = null;
    _hints = const {};
    _machine = TkinterMachine.loading;
  }

  /// A run starts, or supersedes the one before it: nothing of the old one
  /// stays on screen.
  @action
  void startRun() {
    _running = true;
    _output = '';
    _hints = const {};
    _exit = null;
    _windows = const [];
  }

  /// The student pressed Stop. The button turns back at once; the run's end
  /// follows from the machine.
  @action
  void stopRun() => _running = false;

  @action
  void appendOutput(String text) => _output += text;

  @action
  void setWindows(List<VmWindow> windows) => _windows = windows;

  @action
  void addHint(VmHint hint) => _hints = {..._hints, hint};

  /// The run is over. Its windows went with the machine's park.
  @action
  void finishRun(VmExit exit) {
    _exit = exit;
    _running = false;
    _windows = const [];
  }

  @action
  void setDisplayFocused(bool focused) => _displayFocused = focused;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

}
