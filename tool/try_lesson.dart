// Runs one section of a lesson file through the real validation harness, so a
// lesson can be written and checked without the app.
//
// Uses the machine's own `python3`, not the `wasm32-wasi` CPython the app ships.
// The harness program is identical; only the interpreter version differs, so
// check `python3 --version` before trusting a result that turns on a language
// feature.
//
//   dart run tool/try_lesson.dart <lesson.md>
//   dart run tool/try_lesson.dart <lesson.md> <section>
//   dart run tool/try_lesson.dart <lesson.md> <section> --code 'print(42)'
//   dart run tool/try_lesson.dart <lesson.md> <section> --answer answer.py
//
// With no `--code` or `--answer`, the section's own starter block is run.
import 'dart:io';

import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    _bail('usage: dart run tool/try_lesson.dart <lesson.md> [section] [--code <src> | --answer <file>]');
    return;
  }

  final file = File(args.first);
  if (!file.existsSync()) {
    _bail('No such lesson: ${args.first}', code: 66);
    return;
  }

  final Lesson lesson;
  try {
    lesson = Lesson.parse(file.readAsStringSync());
  } on FormatException catch (error) {
    _bail('${args.first} does not parse: ${error.message}', code: 65);
    return;
  }

  final positional = args.skip(1).where((a) => !a.startsWith('--')).toList();
  if (positional.isEmpty) {
    _listSections(lesson);
    return;
  }

  final index = int.tryParse(positional.first);
  if (index == null || index < 0 || index >= lesson.sections.length) {
    _listSections(lesson);
    _bail('Section must be 0..${lesson.sections.length - 1}.');
    return;
  }

  final section = lesson.sections[index];
  if (!section.kind.isAssignment) {
    _bail('Section $index ("${section.title}") is ${section.kind.name} — there is nothing to run.');
    return;
  }

  final code = _readCode(args) ?? section.starter!;
  _report(section, code);
}

void _listSections(Lesson lesson) {
  stdout
    ..writeln('${lesson.title}  (id: ${lesson.id})')
    ..writeln();
  for (final (index, section) in lesson.sections.indexed) {
    // A match-pairs board has no validator to run but is still work, so it is
    // reported by what it holds rather than by what it lacks.
    final runnable = switch (section.kind) {
      final kind when kind.isAssignment => '',
      SectionKind.matchPairs => '   (${section.pairs.length} pairs)',
      _ => '   (nothing to run)',
    };
    final optional = section.optional ? '  [verdieping]' : '';
    stdout.writeln('  $index  ${section.kind.name.padRight(16)} ${section.title}$optional$runnable');
  }
  stdout
    ..writeln()
    ..writeln('Run one with:  dart run tool/try_lesson.dart <lesson.md> <section> --code \'print("hi")\'');
}

String? _readCode(List<String> args) {
  for (final (flag, isPath) in const [('--code', false), ('--answer', true)]) {
    final at = args.indexOf(flag);
    if (at == -1) continue;
    if (at + 1 >= args.length) {
      _bail('$flag needs a value.');
      throw StateError('unreachable');
    }
    final value = args[at + 1];
    return isPath ? File(value).readAsStringSync() : value.replaceAll(r'\n', '\n');
  }
  return null;
}

void _report(LessonSection section, String code) {
  final run = Process.runSync(
    'python3',
    ['-c', PythonAttemptRunner.buildProgram(code: code, validator: section.validator)],
  );
  final result = PythonAttemptRunner.parseResult(
    PythonResult(stdout: '${run.stdout}', stderr: '${run.stderr}', exitCode: run.exitCode),
  );

  stdout
    ..writeln('── ${section.title}  [${section.kind.name}]')
    ..writeln()
    ..writeln('code:')
    ..writeln(_indent(code.trimRight().isEmpty ? '(empty)' : code.trimRight()))
    ..writeln()
    ..writeln('output:')
    ..writeln(_indent(result.output.trimRight().isEmpty ? '(nothing)' : result.output.trimRight()))
    ..writeln();

  if (result.programError case final String error) {
    stdout
      ..writeln('CRASHED — the student sees their own traceback:')
      ..writeln(_indent(error.trimRight()));
  } else if (result.checkMessage case final String message) {
    stdout.writeln('FAILED  — "$message"');
  } else {
    stdout.writeln('PASSED');
  }

  exitCode = result.passed ? 0 : 1;
}

/// Reports a usage problem. Sets [exitCode] rather than calling `exit`, which
/// can kill the process before buffered output is flushed.
void _bail(String message, {int code = 64}) {
  stderr.writeln(message);
  exitCode = code;
}

String _indent(String text) => text.split('\n').map((line) => '    $line').join('\n');
