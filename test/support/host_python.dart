import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';

/// Runs the harness's program through whatever CPython is on this machine.
///
/// `flutter test` has no host for the app's `wasm32-wasi` build, but the wrapper
/// is ordinary Python 3, so this still covers the capture, the traceback
/// trimming, the `output` stripping and the JSON envelope.
Future<AttemptResult> attempt({required String code, String? validator, String? stdin}) async {
  final program = PythonAttemptRunner.buildProgram(code: code, validator: validator);
  // `Process.start` rather than `runSync`, which cannot redirect standard input.
  // Both pipes are drained concurrently so filling one cannot deadlock the run.
  final process = await Process.start('python3', ['-c', program]);
  process.stdin.write(stdin ?? '');
  await process.stdin.close();
  final streams = await Future.wait([
    process.stdout.transform(utf8.decoder).join(),
    process.stderr.transform(utf8.decoder).join(),
  ]);
  final exitCode = await process.exitCode;

  if (exitCode != 0 && streams[0].isEmpty) {
    fail('The harness itself failed to run:\n${streams[1]}');
  }

  return PythonAttemptRunner.parseResult(
    PythonResult(stdout: streams[0], stderr: streams[1], exitCode: exitCode),
  );
}

/// Whether this machine can run [attempt] at all. A test that needs it skips
/// rather than fails without it.
bool get hasPython3 {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
