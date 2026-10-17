import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// What a fresh store over the same storage reads back, which is what a reload
/// produces.
Future<EditorSettings> _reloaded() async {
  final settings = EditorSettings();
  await settings.load();
  return settings;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('nothing saved is the default', () async {
    final settings = await _reloaded();

    expect(settings.tkinterSetup, EditorSettingsBase.defaultTkinterSetup);
    expect(settings.tkinterSetupIsDefault, isTrue);
  });

  test('a change survives a reload', () async {
    await EditorSettings().setTkinterSetup('print("setup")\n');

    final settings = await _reloaded();
    expect(settings.tkinterSetup, 'print("setup")\n');
    expect(settings.tkinterSetupIsDefault, isFalse);
  });

  test('the default is not stored, so a better default reaches everyone who kept it', () async {
    final settings = EditorSettings();
    await settings.setTkinterSetup('print("setup")\n');
    await settings.resetTkinterSetup();

    expect(settings.tkinterSetupIsDefault, isTrue);
    expect(await SharedPreferencesAsync().getString(EditorSettingsBase.tkinterSetupKey), isNull);
  });

  test('storage that refuses is swallowed: the change stands, and a reload falls back', () async {
    SharedPreferencesAsyncPlatform.instance = _RefusingStorage();
    final settings = EditorSettings();

    await expectLater(settings.setTkinterSetup('x'), completes);
    expect(settings.tkinterSetup, 'x');
    expect((await _reloaded()).tkinterSetupIsDefault, isTrue);
  });
}

/// Storage that refuses everything, the way a private window can.
final class _RefusingStorage extends InMemorySharedPreferencesAsync {

  _RefusingStorage() : super.empty();

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) => throw StateError('refused');

  @override
  Future<bool> setString(String key, String value, SharedPreferencesOptions options) => throw StateError('refused');

}
