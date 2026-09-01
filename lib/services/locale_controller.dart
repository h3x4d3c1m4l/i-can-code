import 'dart:ui';

import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'locale_controller.g.dart';

class LocaleController = LocaleControllerBase with _$LocaleController;

/// The app's language, switched from the cog in the header.
///
/// Persisted the same way the theme mode and progress are — **per browser**, and
/// **every read and write swallows its own failure**, so a browser that refuses
/// storage falls back to the default rather than keeping the app from starting.
///
/// **The device's language is the default**, so a student who has never opened
/// the cog gets the app in the language their machine is already in. Dutch is
/// what they land on anyway when the device speaks neither Dutch nor English —
/// see [supported].
abstract class LocaleControllerBase with Store {

  /// The languages the app ships. The **first is the fallback**: it is what
  /// [WidgetsApp] resolves to for a device whose language the app does not
  /// have, which is what keeps the course's own language, Dutch, the last
  /// word rather than an arbitrary one.
  static const List<Locale> supported = [Locale('nl'), Locale('en')];

  /// The localStorage key on web.
  ///
  /// Stored **verbatim** — `SharedPreferencesAsync` adds no `flutter.` prefix —
  /// and JSON-encoded, so the browser holds `locale.language` -> `"en"`. The
  /// key is absent until the student picks something.
  static const String storageKey = 'locale.language';

  final SharedPreferencesAsync _preferences;

  /// The language the student picked, or **null to follow the device** — which
  /// is the default, until they pick one.
  ///
  /// Handed to [WidgetsApp.locale] as-is: null there means Flutter resolves the
  /// device's languages against [supported] itself, landing on [supported]'s
  /// first entry when it has none of them.
  @readonly
  Locale? _locale;

  LocaleControllerBase({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  /// Whether the app is following the device rather than a chosen language.
  @computed
  bool get followsDevice => _locale == null;

  /// Reads what was saved. Called once, before the first frame.
  Future<void> load() async {
    try {
      final stored = await _preferences.getString(storageKey);
      if (stored == null) return;
      // The sentinel is stored rather than the key being removed, so that
      // switching back to the device is a write like any other. It resolves to
      // the same thing as an absent key, which is what makes "never picked"
      // and "picked the device" behave identically.
      _set(stored == _followDevice ? null : _parse(stored));
    } on Object {
      // Treated as "nothing saved", which is following the device.
    }
  }

  /// Switches the language and writes it out. Null follows the device.
  ///
  /// The language changes either way — a storage that will not remember MUST
  /// NOT stop it changing for this session.
  Future<void> setLocale(Locale? locale) async {
    if (_locale == locale) return;
    _set(locale);

    try {
      await _preferences.setString(storageKey, locale?.languageCode ?? _followDevice);
    } on Object {
      // The choice stands for this session either way.
    }
  }

  @action
  void _set(Locale? locale) => _locale = locale;

  static Locale? _parse(String code) {
    for (final locale in supported) {
      if (locale.languageCode == code) return locale;
    }
    return null;
  }

  /// Stands for "follow the device" in storage. Not a language code, so it can
  /// never collide with one.
  static const String _followDevice = 'system';

}
