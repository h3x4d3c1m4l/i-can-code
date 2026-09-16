import 'package:i_can_code/services/python/python_repl.dart';

PythonRepl createPythonRepl() => UnsupportedPythonRepl();

/// Stands in where no host for `python.wasm` exists — every platform but the
/// web, including the Dart VM that `flutter test` runs on.
///
/// Reports `isSupported == false` rather than throwing, so the screen builds and
/// says why instead of crashing a widget test.
class UnsupportedPythonRepl implements PythonRepl {

  @override
  bool get isSupported => false;

  @override
  Stream<ReplEvent> get events => const Stream<ReplEvent>.empty();

  @override
  Future<void> start() async {}

  @override
  void write(String text) {}

  @override
  void endInput() {}

  @override
  bool get isWaitingForInput => false;

  @override
  void dispose() {}

}
