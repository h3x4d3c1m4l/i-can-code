import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which introductions a student has already been through, so each one runs
/// once.
///
/// **Per browser**, like progress, and a convenience rather than a record: every
/// read and write swallows its own failure. A browser that refuses storage
/// shows an introduction again on the next visit, and that is the whole cost.
///
/// Notifies only when it forgets, so the screen in front of the reader can
/// offer its introduction again at once.
class TourStore extends ChangeNotifier {

  static const String storageKey = 'tours.seen';

  final SharedPreferencesAsync _preferences;

  Set<String> _seen = {};

  TourStore({SharedPreferencesAsync? preferences}) : _preferences = preferences ?? SharedPreferencesAsync();

  /// Reads what was saved. Called once, by the initialization screen.
  Future<void> load() async {
    try {
      _seen = {...?await _preferences.getStringList(storageKey)};
    } on Object {
      // Treated as "nothing seen yet".
    }
  }

  bool hasSeen(String id) => _seen.contains(id);

  /// Every id seen so far.
  Set<String> get seen => Set.unmodifiable(_seen);

  /// Records [id] as seen. Holds for this session at once, whether or not the
  /// write lands.
  Future<void> markSeen(String id) async {
    if (!_seen.add(id)) return;

    try {
      await _preferences.setStringList(storageKey, _seen.toList());
    } on Object {
      // Seen for this session either way.
    }
  }

  /// Forgets every introduction, in storage as well as in memory.
  Future<void> clear() async {
    _seen = {};
    notifyListeners();

    try {
      await _preferences.remove(storageKey);
    } on Object {
      // Forgotten for this session either way.
    }
  }

}
