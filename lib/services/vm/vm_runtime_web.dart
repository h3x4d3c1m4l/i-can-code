import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show Color, Rect;
import 'dart:ui_web' as ui_web;

import 'package:i_can_code/services/vm/vm_host_event.dart';
import 'package:i_can_code/services/vm/vm_image.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/services/web/absolute_url_web.dart';
import 'package:web/web.dart' as web;

/// Copied verbatim from `web/vm/` into the build output.
const String _hostPath = 'vm/vm_host.js';
const String _screenPath = 'vm/vm_screen.js';

const String _viewType = 'icc-vm-display';

VmRuntime createVmRuntime() => WebVmRuntime();

extension type _HostModule(JSObject _) implements JSObject {

  external _Vm openVm(_OpenOptions options);

}

extension type _OpenOptions._(JSObject _) implements JSObject {

  external factory _OpenOptions({String baseUrl, JSFunction onEvent, _Screen screen});

}

extension type _ScreenModule(JSObject _) implements JSObject {

  external _Screen createVmScreen(_ScreenOptions options);

}

extension type _ScreenOptions._(JSObject _) implements JSObject {

  external factory _ScreenOptions({int width, int height, JSFunction onFocus});

}

/// `VmScreen` in `web/vm/vm_screen.js`.
extension type _Screen(JSObject _) implements JSObject {

  external web.HTMLElement viewElement(int viewId);

  external void releaseView(int viewId);

  external void setKeyboardEnabled(bool enabled);

  external void setMouseEnabled(bool enabled);

  external void focusElement();

  external void releaseFocus();

  external void setBackground(String css);

  external void setViewport(_Viewport viewport);

  external void destroy();

}

extension type _Viewport._(JSObject _) implements JSObject {

  external factory _Viewport({int x, int y, int width, int height, double scale});

}

/// `Vm` in `web/vm/vm_host.js`.
extension type _Vm(JSObject _) implements JSObject {

  external JSPromise<JSObject> load();

  external _RunHandle run(_Program program);

  external JSPromise<JSAny?> stop();

  external void closeWindow(int xid);

  external JSPromise<JSAny?> destroy();

}

extension type _Program._(JSObject _) implements JSObject {

  external factory _Program({JSObject files, String entry});

}

extension type _RunHandle(JSObject _) implements JSObject {

  external JSNumber get id;

  external JSPromise<JSObject> get ended;

}

extension type _FocusEvent(JSObject _) implements JSObject {

  external bool get inside;

}

/// The machine in `web/vm/`, driven through its `openVm()`.
///
/// The host numbers its own runs; this numbers the runs it hands out, because a
/// run asked for before the host module has even been imported has to have an
/// id at once. [_hostRuns] ties the two together.
class WebVmRuntime implements VmRuntime {

  /// Runtimes whose screens a platform view may still ask for, by the serial
  /// their views carry as creation parameters. More than one is alive while a
  /// screen that replaces another is built before the old one is disposed.
  static final Map<int, WebVmRuntime> _live = {};
  static int _serials = 0;
  static bool _factoryRegistered = false;

  final int _serial = ++_serials;
  final StreamController<VmEvent> _events = StreamController<VmEvent>.broadcast();
  final StreamController<bool> _focus = StreamController<bool>.broadcast();

  late final _WebDisplay _display = _WebDisplay(this);

  _Vm? _vm;
  _Screen? _screen;
  Future<void>? _loading;
  bool _disposed = false;

  /// A `failed` event arrived during the load in flight.
  bool _failureReported = false;

  String? _python;
  String? _tk;

  int _nextRun = 0;

  /// Every run not yet ended, by this runtime's id.
  final Map<int, Completer<VmExit>> _pending = {};

  /// Host run id to this runtime's.
  final Map<int, int> _hostRuns = {};

  /// A run asked for before the host existed. At most one: a second supersedes it.
  ({int id, VmProgram program})? _waiting;

  /// Platform view elements, by view id: each wraps the element the screen gives
  /// that view, or waits for it while the screen does not exist yet.
  final Map<int, web.HTMLDivElement> _views = {};

  WebVmRuntime() {
    _live[_serial] = this;
    _registerFactory();
  }

  @override
  // v86 is WebAssembly; the Cache API and cross-origin isolation are optional.
  bool get isSupported => globalContext.has('WebAssembly');

  @override
  Stream<VmEvent> get events => _events.stream;

  @override
  String? get interpreterVersion => _python;

  @override
  String? get tkVersion => _tk;

  @override
  VmDisplayBinding get display => _display;

  @override
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final vm = await _openHost();
    if (vm == null) {
      _loading = null;
      return;
    }

    _failureReported = false;
    final JSObject result;
    try {
      result = await vm.load().toDart;
    } on Object catch (error) {
      _emit(VmFailed(VmFailure.broken, '$error'));
      _loading = null;
      return;
    }
    final outcome = result.dartify()! as Map<Object?, Object?>;
    if (outcome['type'] != 'failed') return;
    // A failed load is dropped so the next call tries again; the host retries
    // a failed download on its own next load() too.
    _loading = null;
    // A Vm that a newer openVm() destroyed resolves its load as failed and
    // sends no event, which would leave the page loading for good.
    if (!_failureReported) {
      final message = outcome['message'];
      _emit(VmFailed(VmFailure.broken, message is String ? message : 'The VM load failed without an event.'));
    }
  }

  /// Imports the host, builds the screen and opens the page's VM, once.
  Future<_Vm?> _openHost() async {
    if (_vm case final _Vm vm) return vm;

    final _HostModule host;
    final _ScreenModule screens;
    try {
      final modules = await Future.wait([
        importModule(absoluteUrl(_hostPath).toJS).toDart,
        importModule(absoluteUrl(_screenPath).toJS).toDart,
      ]);
      host = modules[0] as _HostModule;
      screens = modules[1] as _ScreenModule;
    } on Object catch (error) {
      _failWaiting('The VM host could not be loaded: $error');
      _emit(VmFailed(VmFailure.network, 'The VM host could not be loaded: $error'));
      return null;
    }
    if (_disposed) return null;
    if (_vm case final _Vm vm) return vm;

    final screen = screens.createVmScreen(
      _ScreenOptions(
        width: vmScreenSize.width.toInt(),
        height: vmScreenSize.height.toInt(),
        onFocus: ((_FocusEvent event) {
          if (!_focus.isClosed) _focus.add(event.inside);
        }).toJS,
      ),
    );
    _screen = screen;
    for (final MapEntry(key: viewId, value: holder) in _views.entries) {
      holder.append(screen.viewElement(viewId));
    }

    final vm = host.openVm(
      _OpenOptions(
        baseUrl: absoluteUrl(vmImagePath),
        onEvent: _onHostEvent.toJS,
        screen: screen,
      ),
    );
    _vm = vm;

    if (_waiting case (:final id, :final program)) {
      _waiting = null;
      _start(vm, id, program);
    }
    return vm;
  }

  @override
  VmRun run(VmProgram program) {
    final id = ++_nextRun;
    final ended = Completer<VmExit>();
    _pending[id] = ended;

    if (_disposed) {
      _finish(id, const VmExit(reason: VmEndReason.stopped));
    } else if (_vm case final _Vm vm) {
      _start(vm, id, program);
    } else {
      if (_waiting case (id: final superseded, program: _)) {
        _finish(superseded, const VmExit(reason: VmEndReason.stopped));
      }
      _waiting = (id: id, program: program);
      unawaited(load());
    }

    return VmRun(id, ended.future);
  }

  void _start(_Vm vm, int id, VmProgram program) {
    final files = JSObject();
    for (final MapEntry(key: name, value: bytes) in program.files.entries) {
      files.setProperty(name.toJS, bytes.toJS);
    }

    final _RunHandle handle;
    try {
      handle = vm.run(_Program(files: files, entry: program.entry));
    } on Object catch (error) {
      // The host throws a TypeError for a program that breaks its rules.
      _finish(id, VmExit(reason: VmEndReason.broken, message: '$error'));
      return;
    }
    _hostRuns[handle.id.toDartDouble.round()] = id;

    // A host that failed after it was ready ends a run inside run(), before its
    // id was known here. The promise settles either way.
    unawaited(
      handle.ended.toDart.then(
        (event) => _finish(id, exitFromHost(event.dartify()! as Map<Object?, Object?>)),
        onError: (Object error) => _finish(id, VmExit(reason: VmEndReason.broken, message: '$error')),
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (_waiting case (:final id, program: _)) {
      _waiting = null;
      _finish(id, const VmExit(reason: VmEndReason.stopped));
    }
    final vm = _vm;
    if (vm == null) return;
    try {
      await vm.stop().toDart;
    } on Object {
      // A park that failed is reported as `failed`; the stop itself is done.
    }
  }

  @override
  void closeWindow(int xid) => _vm?.closeWindow(xid);

  void _onHostEvent(JSObject jsEvent) {
    final event = jsEvent.dartify();
    if (event is! Map<Object?, Object?>) return;

    if (event['type'] == 'log') {
      web.console.debug('[vm] ${event['level']}: ${event['message']}'.toJS);
      return;
    }

    final parsed = parseHostEvent(event, runId: (host) => _hostRuns[host]);
    switch (parsed) {
      case null:
        return;
      case VmReady(:final python, :final tk):
        _python = python;
        _tk = tk;
        _emit(parsed);
      case VmFailed():
        _failureReported = true;
        _emit(parsed);
      case VmRunEnded(:final runId, :final exit):
        _finish(runId, exit);
      default:
        _emit(parsed);
    }
  }

  /// Ends run [id] once: the event first, so everything a caller heard about
  /// the run comes before its end, then the future.
  void _finish(int id, VmExit exit) {
    final ended = _pending.remove(id);
    if (ended == null) return;
    _hostRuns.removeWhere((_, runId) => runId == id);
    _emit(VmRunEnded(id, exit));
    ended.complete(exit);
  }

  void _failWaiting(String message) {
    if (_waiting case (:final id, program: _)) {
      _waiting = null;
      _finish(id, VmExit(reason: VmEndReason.broken, message: message));
    }
  }

  void _emit(VmEvent event) {
    if (_disposed || _events.isClosed) return;
    _events.add(event);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _live.remove(_serial);

    _waiting = null;
    for (final id in [..._pending.keys]) {
      _finish(id, const VmExit(reason: VmEndReason.stopped));
    }

    final vm = _vm;
    _vm = null;
    if (vm != null) {
      unawaited(vm.destroy().toDart.then((_) {}, onError: (Object error) => web.console.error('$error'.toJS)));
    }
    _screen?.destroy();
    _screen = null;
    _views.clear();

    unawaited(_events.close());
    unawaited(_focus.close());
  }

  // The display

  /// One factory for the page, which asks the runtime named in the view's
  /// creation parameters for its element.
  static void _registerFactory() {
    if (_factoryRegistered) return;
    _factoryRegistered = true;

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId, {Object? params}) {
      final runtime = params is int ? _live[params] : null;
      return runtime?._viewElement(viewId) ?? _holder();
    });
  }

  /// A holder of our own around the screen's element: the engine needs an
  /// element now, and the screen may not exist yet.
  web.HTMLDivElement _viewElement(int viewId) {
    final holder = _holder();
    _views[viewId] = holder;
    if (_screen case final _Screen screen) holder.append(screen.viewElement(viewId));
    return holder;
  }

  /// Sized by us: an element without a width and height of its own gets 100%
  /// from the engine along with a console warning.
  static web.HTMLDivElement _holder() {
    final holder = web.HTMLDivElement();
    holder.style
      ..width = '100%'
      ..height = '100%';
    return holder;
  }

  bool _focusIsOnScreen() {
    final active = web.document.activeElement;
    if (active == null) return false;
    return _views.values.any((holder) => holder.contains(active));
  }

}

class _WebDisplay implements VmDisplayBinding {

  final WebVmRuntime _runtime;

  const _WebDisplay(this._runtime);

  @override
  String get viewType => _viewType;

  @override
  Object? get viewParams => _runtime._serial;

  @override
  void releaseView(int viewId) {
    _runtime._views.remove(viewId);
    _runtime._screen?.releaseView(viewId);
  }

  @override
  Stream<bool> get domFocus => _runtime._focus.stream;

  @override
  void setKeyboardEnabled(bool enabled) => _runtime._screen?.setKeyboardEnabled(enabled);

  @override
  void setMouseEnabled(bool enabled) => _runtime._screen?.setMouseEnabled(enabled);

  @override
  void focusElement() => _runtime._screen?.focusElement();

  @override
  void releaseFocus() {
    // Only when focus is still on the screen: focus that has already moved on,
    // into a text field's hidden input, must not be taken from it.
    if (_runtime._focusIsOnScreen()) _runtime._screen?.releaseFocus();
  }

  @override
  void showRegion(Rect region, double scale) {
    _runtime._screen?.setViewport(
      _Viewport(
        x: region.left.round(),
        y: region.top.round(),
        width: region.width.round(),
        height: region.height.round(),
        scale: scale,
      ),
    );
  }

  @override
  void setBackground(Color color) {
    int channel(double value) => (value * 255).round();
    _runtime._screen?.setBackground('rgb(${channel(color.r)} ${channel(color.g)} ${channel(color.b)} / ${color.a})');
  }

}
