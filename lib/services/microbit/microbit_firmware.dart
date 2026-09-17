import 'package:flutter/services.dart';

/// The MicroPython build a flashed program is embedded in.
///
/// Fetched by `just fetch-microbit-firmware` rather than committed, so a clone
/// that has not run it gets a [FlutterError] here and the screen says so.
const String _firmwareAsset = 'assets/microbit/micropython-microbit-v2.1.1.hex';

String? _cached;

/// Reads the firmware hex, once per session.
///
/// About 1.2 MB of text. Cached because every flash needs the whole of it, and
/// re-reading an asset that cannot change is a pause the reader would feel.
Future<String> loadMicrobitFirmware({AssetBundle? bundle}) async {
  final cached = _cached;
  if (cached != null) {
    return cached;
  }

  final loaded = await (bundle ?? rootBundle).loadString(_firmwareAsset);
  _cached = loaded;

  return loaded;
}
