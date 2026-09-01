import 'dart:ui';

import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_mode_controller.g.dart';

class ThemeModeController = ThemeModeControllerBase with _$ThemeModeController;

/// What the student picked in the cog menu.
enum AppThemeMode {

  system,
  light,
  dark;

  /// Which brightness this mode means, given what the platform is asking for.
  Brightness brightnessFor(Brightness platform) => switch (this) {
    AppThemeMode.system => platform,
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
  };

  /// [name] back to a value, or null if it is not one. Tolerant on purpose:
  /// storage is shared with whatever an older build wrote there.
  static AppThemeMode? parse(String? value) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }

}

/// The app's light/dark choice, switched from the cog in the header.
///
/// Persisted, unlike the locale controller: a student who picks dark should not
/// have to pick it again on the next visit. Persisted the same way progress is
/// — **per browser**, and **every read and write swallows its own failure**, so
/// a browser that refuses storage falls back to [AppThemeMode.system] rather
/// than keeping the app from starting.
abstract class ThemeModeControllerBase with Store {

  /// The localStorage key on web.
  ///
  /// `SharedPreferencesAsync` stores it **verbatim** — no `flutter.` prefix —
  /// JSON-encoded, so the browser holds `theme.mode` -> `"dark"`. `web/index.html`
  /// reads this exact key to paint its splash in the right mode, and MUST be
  /// changed alongside it.
  static const String storageKey = 'theme.mode';

  final SharedPreferencesAsync _preferences;

  @readonly
  AppThemeMode _mode = AppThemeMode.system;

  ThemeModeControllerBase({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  /// Reads what was saved. Called once, before the first frame.
  Future<void> load() async {
    try {
      final stored = AppThemeMode.parse(await _preferences.getString(storageKey));
      if (stored != null) _set(stored);
    } on Object {
      // Treated as "nothing saved", which is `system`.
    }
  }

  /// Switches the mode and writes it out. The mode changes either way — a
  /// storage that will not remember MUST NOT stop it changing for this session.
  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _set(mode);

    try {
      await _preferences.setString(storageKey, mode.name);
    } on Object {
      // The choice stands for this session either way.
    }
  }

  @action
  void _set(AppThemeMode mode) => _mode = mode;

}
