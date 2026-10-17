import 'dart:ui' show Color, Rect;

import 'package:i_can_code/services/vm/vm_runtime.dart';

VmRuntime createVmRuntime() => UnsupportedVmRuntime();

/// Stands in where no host for the machine exists: every platform but the web,
/// including the Dart VM that `flutter test` runs on, and a build without the
/// image.
///
/// Reports `isSupported == false` and throws nothing, so the screen builds and
/// says why instead of crashing a widget test.
class UnsupportedVmRuntime implements VmRuntime {

  static const VmExit _unavailable = VmExit(
    reason: VmEndReason.broken,
    message: 'There is no machine on this platform.',
  );

  int _nextRun = 0;

  @override
  bool get isSupported => false;

  @override
  Stream<VmEvent> get events => const Stream<VmEvent>.empty();

  @override
  String? get interpreterVersion => null;

  @override
  String? get tkVersion => null;

  @override
  VmDisplayBinding get display => const _NoDisplay();

  @override
  Future<void> load() async {}

  @override
  VmRun run(VmProgram program) => VmRun(++_nextRun, Future.value(_unavailable));

  @override
  Future<void> stop() async {}

  @override
  void closeWindow(int xid) {}

  @override
  void dispose() {}

}

class _NoDisplay implements VmDisplayBinding {

  const _NoDisplay();

  @override
  String get viewType => '';

  @override
  Object? get viewParams => null;

  @override
  void releaseView(int viewId) {}

  @override
  Stream<bool> get domFocus => const Stream<bool>.empty();

  @override
  void setKeyboardEnabled(bool enabled) {}

  @override
  void setMouseEnabled(bool enabled) {}

  @override
  void focusElement() {}

  @override
  void releaseFocus() {}

  @override
  void showRegion(Rect region, double scale) {}

  @override
  void setBackground(Color color) {}

}
