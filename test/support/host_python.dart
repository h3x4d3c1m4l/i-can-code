import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/services/python/section_attempt.dart';

/// The pytest that `tool/bake_pytest.py` bakes into the app. A host with
/// another one still runs the tests, but may word its output differently.
const String kPytestVersion = '9.1.1';

/// Runs the harness's program through whatever CPython is on this machine.
///
/// `flutter test` has no host for the app's `wasm32-wasi` build, but the wrapper
/// is ordinary Python 3, so this still covers the capture, the traceback
/// trimming, the `output` stripping and the JSON envelope.
Future<AttemptResult> attempt({
  required String code,
  String? validator,
  String? stdin,
  Map<String, String> files = const {},
  PythonRunMode mode = PythonRunMode.script,
  String fileName = 'main.py',
}) async {
  final result = await runOnHost(
    PythonAttemptRunner.buildProgram(code: code, validator: validator, files: files, mode: mode, fileName: fileName),
    stdin: stdin,
  );
  return PythonAttemptRunner.parseResult(result);
}

/// Runs [program] the way [attempt] does, and hands back what came out of it
/// unread, for a test that has to cut it first.
Future<PythonResult> runOnHost(String program, {String? stdin}) async {
  // Run as main.py in its own directory, the way web/python/python_worker.js
  // runs it. With `-c` there is no main.py on disk, which hid that tracebacks
  // quoted the wrapper's lines instead of the student's.
  final dir = await Directory.systemTemp.createTemp('icc_attempt_');
  addTearDown(() => dir.delete(recursive: true));
  await File('${dir.path}/main.py').writeAsString(program);
  // `Process.start` rather than `runSync`, which cannot redirect standard input.
  // Both pipes are drained concurrently so filling one cannot deadlock the run.
  final process = await Process.start('python3', ['main.py'], workingDirectory: dir.path);
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

  return PythonResult(stdout: streams[0], stderr: streams[1], exitCode: exitCode);
}

/// Runs [code] the way the lesson screen runs it for [section].
Future<AttemptResult> attemptSection(LessonSection section, String code) => attempt(
  code: code,
  validator: section.validator,
  stdin: section.stdin,
  files: section.files,
  mode: section.runMode,
  fileName: section.fileName,
);

/// Whether this machine can run [attempt] at all. A test that needs it skips
/// rather than fails without it.
bool get hasPython3 {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Whether the host python can also run a [PythonRunMode.pytest] attempt.
/// Install it with `pip install pytest==$kPytestVersion`.
final bool hasPytest = () {
  if (!hasPython3) return false;
  final result = Process.runSync('python3', ['-c', 'import pytest; print(pytest.__version__)']);
  if (result.exitCode != 0) return false;
  final version = (result.stdout as String).trim();
  if (version != kPytestVersion) {
    // ignore: avoid_print
    print('Host pytest is $version; the app ships $kPytestVersion.');
  }
  return true;
}();
