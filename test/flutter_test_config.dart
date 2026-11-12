import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/views/components/code_editor/code_forge_editor.dart';

import 'support/test_assets.dart';

/// Runs before every test file under `test/`.
///
/// A focused editor's caret blinks on a ticker, so `pumpAndSettle` would never
/// return on a screen whose editor has the keyboard. The one test of the blink
/// itself turns it back on.
///
/// Assets come from [testAsset], which keeps code_forge's icon fonts from
/// loading. A test that answers `flutter/assets` itself MUST use it too.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  CodeForgeEditor.debugCaretBlinks = false;
  TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMessageHandler(
    'flutter/assets',
    (message) => testAsset(utf8.decode(message!.buffer.asUint8List())),
  );
  await testMain();
}
