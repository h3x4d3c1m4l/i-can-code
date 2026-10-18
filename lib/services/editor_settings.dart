import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'editor_settings.g.dart';

class EditorSettings = EditorSettingsBase with _$EditorSettings;

/// What the code-editor settings screen sets, kept in this browser.
///
/// Per browser and swallowing every failure, like `ThemeModeController`. A
/// value equal to its default is not stored, so a default improved later still
/// reaches everyone who never changed it.
///
/// Written at once rather than after a pause, as `CodeDraftStore` does: this
/// screen is visited rarely, and a few writes per edit cost nothing on the web.
abstract class EditorSettingsBase with Store {

  static const String tkinterSetupKey = 'settings.tkinterSetup';

  /// Turtle's defaults suited to the machine behind the Tkinter page. Dutch,
  /// like the sample program on that page. `docs/vm-build.md`, "Turtle", has
  /// the measurements behind both.
  static const String defaultTkinterSetup = '''import turtle

# Turtle wacht na elk beeld van een animatie 10 ms. Deze machine tekent
# trager dan een gewone computer, en zonder die pauze loopt de turtle
# ongeveer even snel als daar.
turtle._CFG["delay"] = 0

# Anders wordt het venster 400 x 450 op het scherm van 800 x 600: te smal
# voor het tekenvlak, dat dan schuifbalken krijgt.
turtle._CFG["width"] = 600
turtle._CFG["height"] = 500
''';

  final SharedPreferencesAsync _preferences;

  /// Python the machine runs before every program, in the same interpreter:
  /// on the Tkinter page and in a project on `runtime: tkinter`. The image's
  /// prelude runs it from `vmSetupFile`.
  @readonly
  String _tkinterSetup = defaultTkinterSetup;

  EditorSettingsBase({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  @computed
  bool get tkinterSetupIsDefault => _tkinterSetup == defaultTkinterSetup;

  /// Reads what was saved. Called once, by the initialization screen.
  Future<void> load() async {
    try {
      final stored = await _preferences.getString(tkinterSetupKey);
      if (stored != null) _setTkinterSetup(stored);
    } on Object {
      // Treated as "nothing saved", which is the default.
    }
  }

  /// Changes the setup for this session and writes it out. A storage that will
  /// not remember MUST NOT stop it changing.
  Future<void> setTkinterSetup(String code) async {
    if (_tkinterSetup == code) return;
    _setTkinterSetup(code);

    try {
      if (code == defaultTkinterSetup) {
        await _preferences.remove(tkinterSetupKey);
      } else {
        await _preferences.setString(tkinterSetupKey, code);
      }
    } on Object {
      // The change stands for this session either way.
    }
  }

  Future<void> resetTkinterSetup() => setTkinterSetup(defaultTkinterSetup);

  @action
  void _setTkinterSetup(String code) => _tkinterSetup = code;

}
