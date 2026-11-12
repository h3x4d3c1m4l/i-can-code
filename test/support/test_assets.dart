import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// An asset as the test binding serves it, read from the bundle `flutter test`
/// builds, except code_forge's icon fonts, which never arrive.
///
/// code_forge loads those fonts itself whenever an editor is built. A font that
/// loads has the engine announce new system fonts, which schedules a frame, and
/// that announcement comes in real time, after the test's last pump: Flutter
/// 3.50 then fails the test for an animation still running. The app draws
/// nothing in those fonts, so a load that waits forever changes nothing else.
Future<ByteData?> testAsset(String key) {
  if (key.startsWith('packages/code_forge/assets/icons/')) return Completer<ByteData?>().future;

  // The same lookup as flutter_test's own mockFlutterAssets, which a handler
  // set here replaces.
  final folder = Platform.environment['UNIT_TEST_ASSETS'];
  if (folder == null) return SynchronousFuture(null);
  var file = File('$folder/$key');
  final own = 'packages/${Platform.environment['APP_NAME']}/';
  if (!file.existsSync() && key.startsWith(own)) file = File('$folder/${key.substring(own.length)}');
  if (!file.existsSync()) return SynchronousFuture(null);
  return SynchronousFuture(Uint8List.fromList(file.readAsBytesSync()).buffer.asByteData());
}
