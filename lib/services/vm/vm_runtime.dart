import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color, Rect, Size;

import 'package:i_can_code/services/vm/vm_image.dart';
// The web host is the only one that exists; everything else, the Dart VM that
// `flutter test` runs on included, falls through to the stub, which reports
// `isSupported == false` rather than throwing.
import 'package:i_can_code/services/vm/vm_runtime_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/vm/vm_runtime_web.dart' as impl;
import 'package:i_can_code/services/vm/vm_runtime_stub.dart' as stub;

/// The guest's screen, in guest pixels. Fixed by the image: 4 MiB of VGA memory
/// holds no larger frame twice, see `docs/vm-build.md`.
const Size vmScreenSize = Size(800, 600);

/// The file the image's prelude runs before the entry, in the same interpreter,
/// and removes before the entry starts. Coupled to `SETUP` in
/// `vm/image/files/usr/lib/icc/prelude.py`.
const String vmSetupFile = 'icc_setup.py';

/// A program for the machine: flat files and the one run as `__main__`.
class VmProgram {

  /// Names MUST match `[A-Za-z0-9._-]{1,64}` and not start with a dot; at most
  /// 64 files and 8 MiB together. The host checks both.
  final Map<String, Uint8List> files;

  /// MUST be one of [files].
  final String entry;

  const VmProgram({required this.files, required this.entry});

  /// One file of source text, which is every program the app sends today, with
  /// [setup] as [vmSetupFile] beside it. A blank [setup] sends no file at all.
  factory VmProgram.source(String source, {String entry = 'main.py', String setup = ''}) => VmProgram(
    files: {
      entry: utf8.encode(source),
      if (setup.trim().isNotEmpty) vmSetupFile: utf8.encode(setup),
    },
    entry: entry,
  );

}

/// Why a run ended. Every run ends exactly once, with one of these.
enum VmEndReason {

  /// The program ended by itself, a crash included: that is an [exit] with a
  /// non-zero code and a traceback on stderr, not a harness failure.
  exit,

  /// The close button on its window had to kill it, because the window would
  /// not take the close request.
  closed,

  /// The kernel's OOM killer took it.
  outOfMemory,

  /// [VmRuntime.stop], a newer [VmRuntime.run] or [VmRuntime.dispose] ended it.
  stopped,

  /// The machine stopped answering. A harness failure.
  unresponsive,

  /// A file of the machine's own could not be downloaded. A harness failure.
  fetch,

  /// The harness refused or lost the run. A harness failure.
  broken;

  /// The machine failed, not the program. A caller MUST NOT phrase it as a
  /// mistake the student made.
  bool get isHarnessFailure => this == unresponsive || this == fetch || this == broken;

}

/// How a run ended.
class VmExit {

  final VmEndReason reason;

  /// The exit status, or null when a signal ended the process or the run never
  /// reached the guest.
  final int? code;

  /// The signal that ended the process, or null.
  final int? signal;

  /// The program printed more than the host forwards, and the rest was dropped.
  final bool truncated;

  /// How long the program ran in the guest, leaving out time the tab was hidden.
  /// Null when it never started.
  final Duration? duration;

  /// The harness's own words, in English, for a developer. Never for the student.
  final String? message;

  const VmExit({required this.reason, this.code, this.signal, this.truncated = false, this.duration, this.message});

  /// Ended by the caller. A caller MUST NOT present it as a verdict: the
  /// student asked for it, and the program did nothing wrong.
  bool get stopped => reason == VmEndReason.stopped;

  /// Whether the program itself went wrong: a non-zero exit or a signal it
  /// brought on itself. False for every harness failure and for a stop.
  bool get failed => reason == VmEndReason.exit && ((code ?? 0) != 0 || signal != null);

}

/// One of the run's top-level windows.
///
/// There is no window manager in the guest, so the app draws each frame itself
/// from these.
class VmWindow {

  /// The X window id. [VmRuntime.closeWindow] names a window by it.
  final int xid;

  /// Empty when the program set none.
  final String title;

  /// Where it sits on the [vmScreenSize] screen, in guest pixels. With no
  /// window manager a Tk toplevel opens at +0+0.
  final int x;
  final int y;

  /// The inside size in guest pixels. There is no decoration around it.
  final int width;
  final int height;

  /// Viewable. False while it is withdrawn or iconified.
  final bool mapped;

  /// The program's main window: the Tk root. At most one window has it.
  final bool isRoot;

  /// The window a dialog belongs to, or null.
  final int? transientFor;

  const VmWindow({
    required this.xid,
    required this.title,
    required this.mapped,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.isRoot = false,
    this.transientFor,
  });

}

/// Something the guest noticed about a program that the student should hear.
enum VmHint {

  /// A Tk root was created and the program ended without `mainloop()`, so its
  /// window closed at once or never appeared.
  tkNoMainloop,

}

/// Why the machine as a whole cannot run programs.
enum VmFailure {

  /// The bundle could not be downloaded.
  network,

  /// The bundle speaks another protocol than this page. A reload fixes it.
  incompatible,

  /// A file of the machine's own could not be downloaded while it started.
  fetch,

  /// The machine did not answer.
  unresponsive,

  /// A newer page took the machine: the host keeps one per tab. A new runtime
  /// takes it back.
  replaced,

  /// Anything else in the harness.
  broken,

}

/// Something the machine did.
sealed class VmEvent {

  const VmEvent();

}

/// What a student waits through while the machine loads, in order.
enum VmLoadPhase {

  /// The bundle arrives: from the network, or from the browser's storage.
  download,

  /// The saved machine is decompressed, once per page.
  unpack,

  /// The machine starts and answers.
  start,

}

/// How far [VmRuntime.load] is.
class VmLoadProgress extends VmEvent {

  final VmLoadPhase phase;

  /// Bytes of the bundle held so far, of [total]. Both count the files as the
  /// image names them, whatever the server compressed on the way.
  final int loaded;
  final int total;

  /// Of [loaded], what the browser had kept from an earlier visit.
  final int cached;

  /// Over the network, smoothed over a few seconds. Null until there has been
  /// enough of the download to measure.
  final double? bytesPerSecond;

  /// What is left at [bytesPerSecond]. Null with it.
  final Duration? remaining;

  /// Nothing has arrived for a few seconds, or a request waits to be tried
  /// again. The download goes on by itself once the connection lets it.
  final bool stalled;

  /// False when the browser has no room to keep the machine, or no storage at
  /// all: it works, and is downloaded again next time.
  final bool keeps;

  /// The browser guesses the connection is slow. A hint, never a promise.
  final bool slowConnection;

  const VmLoadProgress(
    this.loaded,
    this.total, {
    this.phase = VmLoadPhase.download,
    this.cached = 0,
    this.bytesPerSecond,
    this.remaining,
    this.stalled = false,
    this.keeps = true,
    this.slowConnection = false,
  });

  /// Everything is held and nothing is left to download.
  bool get downloaded => total > 0 && loaded >= total;

}

/// The machine is parked and waiting for a program.
class VmReady extends VmEvent {

  /// What the guest's interpreter calls itself, such as `Python 3.12.12`.
  final String? python;

  /// Tk's patch level, such as `8.6.16`.
  final String? tk;

  const VmReady({this.python, this.tk});

}

/// The machine cannot run programs. A later [VmRuntime.load] may still work for
/// a failed download; after the machine was ready it needs a new runtime.
class VmFailed extends VmEvent {

  final VmFailure failure;

  /// English, for a developer. A caller MUST NOT show it as the page's own
  /// words: [failure] is what to word.
  final String message;

  const VmFailed(this.failure, this.message);

}

/// The program is running. [warm] is false when a cold interpreter took it,
/// which only happens after a park failed to bring the warm one back.
class VmRunStarted extends VmEvent {

  final int runId;
  final bool warm;

  const VmRunStarted(this.runId, {required this.warm});

}

/// What the program printed, already decoded, so a character split across two
/// frames arrives whole.
class VmOutput extends VmEvent {

  final int runId;
  final String text;
  final bool fromStderr;

  const VmOutput(this.runId, this.text, {required this.fromStderr});

}

/// The run's top-level windows, bottom to top in stacking order, as a complete
/// list every time.
class VmWindows extends VmEvent {

  final int runId;
  final List<VmWindow> windows;

  const VmWindows(this.runId, this.windows);

}

class VmRunHint extends VmEvent {

  final int runId;
  final VmHint hint;

  const VmRunHint(this.runId, this.hint);

}

/// The run is over, exactly once per run. Nothing about it follows.
class VmRunEnded extends VmEvent {

  final int runId;
  final VmExit exit;

  const VmRunEnded(this.runId, this.exit);

}

/// A run the runtime accepted.
class VmRun {

  /// What every event about this run carries.
  final int id;

  /// Completes once, however the run ends. Never completes with an error.
  final Future<VmExit> ended;

  const VmRun(this.id, this.ended);

}

/// A Linux machine with Python and Tk, emulated in the page, that runs one
/// program at a time and draws its windows.
///
/// Beside `PythonRuntime`, not above or below it. That one runs a program to
/// completion and hands back what it printed, which is what every lesson check
/// is built on. This one hosts a session that ends when the program ends or the
/// student ends it.
///
/// **Created by the screen that uses it and disposed when that screen goes.**
/// The machine costs about 300 MB of tab memory whether it runs or not, and only
/// disposing it gives that back.
abstract class VmRuntime {

  /// False where this browser cannot host the machine, and on every platform
  /// but the web. The screen then says why rather than disappearing.
  bool get isSupported;

  /// Everything the machine does. Broadcast, and closed on [dispose].
  Stream<VmEvent> get events;

  /// What the guest's python3 reported, such as `Python 3.12.12`. Null until
  /// the machine is ready, and always on the stub, so a caller MUST have
  /// something to show in its place.
  String? get interpreterVersion;

  /// Tk's patch level, null under the same conditions.
  String? get tkVersion;

  /// The screen's element, for `VmDisplay`.
  VmDisplayBinding get display;

  /// Downloads the machine and parks it, reporting [VmLoadProgress] and then
  /// [VmReady] or [VmFailed]. Never throws.
  ///
  /// Calls share one load. A failed download is dropped so the next call tries
  /// again.
  Future<void> load();

  /// Runs [program], loading the machine first when that has not happened.
  ///
  /// Supersedes rather than refuses: a run in flight ends as
  /// [VmEndReason.stopped] and this one starts after it. Output, windows and
  /// hints arrive on [events] tagged with the returned id. A program the host
  /// refuses ends at once as [VmEndReason.broken].
  VmRun run(VmProgram program);

  /// Ends the run in flight for the caller at once, and resolves once the
  /// machine is parked again. Depends on nothing the program or the guest does.
  Future<void> stop();

  /// What the close button on a window's frame does: the program's own close
  /// path, as a window manager would. A program that ignores it keeps running,
  /// and [stop] still works.
  void closeWindow(int xid);

  /// Ends the run in flight and frees the machine. Nothing is emitted after.
  void dispose();

}

/// The platform view the guest's screen is shown in, and the input wiring
/// around it.
///
/// Here rather than in the widget so the widget never imports `dart:ui_web` or
/// `package:web`, and still builds under `flutter test`.
abstract class VmDisplayBinding {

  /// The platform view type, registered once per page.
  String get viewType;

  /// Passed to the view as its creation parameters: which runtime's screen the
  /// view shows.
  Object? get viewParams;

  /// Flutter is disposing the platform view [viewId].
  void releaseView(int viewId);

  /// DOM focus entering (true) or leaving (false) the screen's element.
  Stream<bool> get domFocus;

  /// The guest's keys listen on the whole window, so they MUST be off whenever
  /// the display does not hold focus.
  void setKeyboardEnabled(bool enabled);

  void setMouseEnabled(bool enabled);

  /// Moves DOM focus onto the screen's element.
  void focusElement();

  /// Moves DOM focus off the screen's element, if it is there, without leaving
  /// the Flutter view.
  void releaseFocus();

  /// Shows [region] of the guest's screen, in guest pixels, at [scale] logical
  /// pixels per guest pixel. The platform view MUST be laid out at [region]'s
  /// size times [scale]: it clips to its own box, and a click maps through it.
  void showRegion(Rect region, double scale);

  /// The colour around the screen where its view is larger than the screen.
  void setBackground(Color color);

}

/// The machine for this platform, or the stub in a build without the image
/// ([vmImageIncluded]), so nothing asks for a download that can only 404.
VmRuntime createVmRuntime() => vmImageIncluded ? impl.createVmRuntime() : stub.createVmRuntime();
