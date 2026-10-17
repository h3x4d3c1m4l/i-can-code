import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color, Rect;

import 'package:i_can_code/services/vm/vm_runtime.dart';

/// A machine that does what `web/vm/vm_host.js` promises and nothing else,
/// driven by the test: it supersedes and stops the way the host does, and every
/// event a real guest would send is the test's to send.
class FakeVmRuntime implements VmRuntime {

  final bool supported;

  final StreamController<VmEvent> _events = StreamController<VmEvent>.broadcast();

  @override
  final FakeDisplayBinding display = FakeDisplayBinding();

  int loads = 0;
  int stops = 0;
  bool disposed = false;
  final List<int> closedWindows = [];

  /// Every program asked for, in order, with the id it was given.
  final List<({int id, VmProgram program})> runs = [];

  final Map<int, Completer<VmExit>> _open = {};
  int _nextRun = 0;

  FakeVmRuntime({this.supported = true});

  /// The source of the last program, as the student typed it.
  String get lastSource => utf8.decode(runs.last.program.files[runs.last.program.entry]!);

  int get lastRunId => runs.last.id;

  @override
  bool get isSupported => supported;

  @override
  Stream<VmEvent> get events => _events.stream;

  @override
  String? interpreterVersion;

  @override
  String? tkVersion;

  @override
  Future<void> load() async => loads++;

  @override
  VmRun run(VmProgram program) {
    // The host ends the run it supersedes before the new one exists.
    for (final id in [..._open.keys]) {
      end(id, const VmExit(reason: VmEndReason.stopped));
    }
    final id = ++_nextRun;
    final ended = Completer<VmExit>();
    _open[id] = ended;
    runs.add((id: id, program: program));
    return VmRun(id, ended.future);
  }

  @override
  Future<void> stop() async {
    stops++;
    for (final id in [..._open.keys]) {
      end(id, const VmExit(reason: VmEndReason.stopped));
    }
  }

  @override
  void closeWindow(int xid) => closedWindows.add(xid);

  /// Sends [event] as the machine would.
  void emit(VmEvent event) {
    if (!disposed) _events.add(event);
  }

  void ready({String python = 'Python 3.12.12', String tk = '8.6.16'}) {
    interpreterVersion = python;
    tkVersion = tk;
    emit(VmReady(python: python, tk: tk));
  }

  /// Ends run [id] the one time a run ends, as the host does.
  void end(int id, VmExit exit) {
    final ended = _open.remove(id);
    if (ended == null) return;
    emit(VmRunEnded(id, exit));
    ended.complete(exit);
  }

  @override
  void dispose() {
    for (final id in [..._open.keys]) {
      end(id, const VmExit(reason: VmEndReason.stopped));
    }
    disposed = true;
    unawaited(_events.close());
  }

}

/// Records what the display asked of the page, and lets a test move DOM focus.
class FakeDisplayBinding implements VmDisplayBinding {

  final StreamController<bool> _focus = StreamController<bool>.broadcast(sync: true);

  bool keyboardEnabled = false;
  bool mouseEnabled = false;
  int elementFocused = 0;
  int focusReleased = 0;
  final List<int> released = [];
  Color? background;

  /// What [showRegion] was last asked for, and how many times it was.
  Rect? region;
  double? scale;
  int regionsShown = 0;

  /// Every value the mouse was set to, in order.
  final List<bool> mouseHistory = [];

  @override
  String get viewType => 'fake-vm-display';

  @override
  Object? get viewParams => null;

  @override
  void releaseView(int viewId) => released.add(viewId);

  @override
  Stream<bool> get domFocus => _focus.stream;

  /// DOM focus arriving on (true) or leaving (false) the screen's element.
  void moveDomFocus({required bool inside}) => _focus.add(inside);

  @override
  void setKeyboardEnabled(bool enabled) => keyboardEnabled = enabled;

  @override
  void setMouseEnabled(bool enabled) {
    mouseEnabled = enabled;
    mouseHistory.add(enabled);
  }

  @override
  void focusElement() => elementFocused++;

  @override
  void releaseFocus() => focusReleased++;

  @override
  void showRegion(Rect region, double scale) {
    this.region = region;
    this.scale = scale;
    regionsShown++;
  }

  @override
  void setBackground(Color color) => background = color;

}
