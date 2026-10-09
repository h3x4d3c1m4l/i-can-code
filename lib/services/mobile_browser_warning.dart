import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the app runs in a browser on a phone or a tablet, where the code
/// editor is known to misbehave.
///
/// `re_editor` reads [defaultTargetPlatform] and takes a path written for a
/// native app. In a browser that path loses the space bar of a hardware
/// keyboard and deletes a character on a tap:
/// https://github.com/reqable/re-editor/issues/58
///
/// [isWeb] is half of the test on purpose. A native build reports the same
/// platform and has none of the trouble.
bool isMobileBrowser({bool isWeb = kIsWeb, TargetPlatform? platform}) =>
    isWeb && const {TargetPlatform.iOS, TargetPlatform.android}.contains(platform ?? defaultTargetPlatform);

/// The warning a mobile browser gets before the app opens, and whether the
/// reader already chose to go on past it.
///
/// **Per browser**, like `TourStore`, and a convenience the same way: every
/// read and write swallows its own failure. A browser that refuses storage
/// shows the warning again on the next visit, and that is the whole cost.
class MobileBrowserWarning {

  static const String storageKey = 'mobileWarning.dismissed';

  final SharedPreferencesAsync _preferences;
  final bool _applies;

  bool _dismissed = false;

  /// [applies] defaults to [isMobileBrowser]. A test passes it, because
  /// [kIsWeb] is a constant false there.
  MobileBrowserWarning({SharedPreferencesAsync? preferences, bool? applies})
    : _preferences = preferences ?? SharedPreferencesAsync(),
      _applies = applies ?? isMobileBrowser();

  /// Whether the warning still has to be shown.
  bool get due => _applies && !_dismissed;

  bool get dismissed => _dismissed;

  /// Reads what was saved. Called once, by the initialization screen.
  Future<void> load() async {
    try {
      _dismissed = await _preferences.getBool(storageKey) ?? false;
    } on Object {
      // Treated as "not dismissed yet".
    }
  }

  /// Records that the reader went on. Holds for this session at once, whether
  /// or not the write lands.
  Future<void> dismiss() async {
    _dismissed = true;

    try {
      await _preferences.setBool(storageKey, true);
    } on Object {
      // Dismissed for this session either way.
    }
  }

  /// Forgets the choice, in storage as well as in memory.
  Future<void> clear() async {
    _dismissed = false;

    try {
      await _preferences.remove(storageKey);
    } on Object {
      // Forgotten for this session either way.
    }
  }

}
