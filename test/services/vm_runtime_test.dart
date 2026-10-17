import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';

void main() {
  group('the machine on a platform without one', () {
    // This is what `flutter test` gets: the conditional import falls through to
    // the stub on the Dart VM. The page must be able to build and explain itself
    // here, which it cannot if any of this throws.

    test('reports itself unsupported and names no interpreter', () {
      final runtime = createVmRuntime();

      expect(runtime.isSupported, isFalse);
      expect(runtime.interpreterVersion, isNull);
      expect(runtime.tkVersion, isNull);
      expect(runtime.dispose, returnsNormally);
    });

    test('has events that produce nothing and end', () async {
      expect(await createVmRuntime().events.toList(), isEmpty);
    });

    test('accepts every verb without doing anything', () async {
      final runtime = createVmRuntime();

      await expectLater(runtime.load(), completes);
      await expectLater(runtime.stop(), completes);
      expect(() => runtime.closeWindow(1), returnsNormally);
    });

    test('ends a run at once, as the machine failing rather than the program', () async {
      final exit = await createVmRuntime().run(VmProgram.source('print(1)')).ended;

      expect(exit.reason.isHarnessFailure, isTrue);
      expect(exit.failed, isFalse);
    });

    test('has a display that does nothing', () {
      final display = createVmRuntime().display;

      expect(() {
        display
          ..setKeyboardEnabled(true)
          ..setMouseEnabled(true)
          ..focusElement()
          ..releaseFocus()
          ..setBackground(const Color(0xFF000000))
          ..showRegion(const Rect.fromLTWH(0, 0, 200, 100), 1)
          ..releaseView(1);
      }, returnsNormally);
    });
  });

  test('a program from source is one main.py, as UTF-8', () {
    final program = VmProgram.source('print("één")');

    expect(program.entry, 'main.py');
    expect(program.files.keys, ['main.py']);
    expect(utf8.decode(program.files['main.py']!), 'print("één")');
  });

  test('a setup goes beside it under the name the prelude looks for, and a blank one not at all', () {
    final program = VmProgram.source('print(1)', setup: 'import turtle\n');

    expect(program.entry, 'main.py');
    expect(utf8.decode(program.files[vmSetupFile]!), 'import turtle\n');
    expect(VmProgram.source('print(1)', setup: ' \n').files.keys, ['main.py']);
  });
}
