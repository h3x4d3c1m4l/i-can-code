import 'package:i_can_code/services/python/python_runtime.dart';

PythonRuntime createPythonRuntime() => const UnsupportedPythonRuntime();

/// Stands in where no host for `python.wasm` exists — every platform but the
/// web, including the Dart VM that `flutter test` runs on.
///
/// Reports `isSupported == false` rather than throwing, so a screen that shows
/// code and output stays usable and only running is unavailable.
class UnsupportedPythonRuntime implements PythonRuntime {

  const UnsupportedPythonRuntime();

  @override
  bool get isSupported => false;

  @override
  Future<void> ready() async {}

  @override
  Future<PythonResult> run(String code, {String stdin = ''}) async =>
      const PythonResult.failure('Running Python is not available on this platform yet.');

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

}
