import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('starts on system', () => expect(ThemeModeController().mode, AppThemeMode.system));

  test('system follows the platform, the other two do not', () {
    expect(AppThemeMode.system.brightnessFor(Brightness.dark), Brightness.dark);
    expect(AppThemeMode.system.brightnessFor(Brightness.light), Brightness.light);

    // The point of an explicit choice: a dark machine MUST NOT override it.
    expect(AppThemeMode.light.brightnessFor(Brightness.dark), Brightness.light);
    expect(AppThemeMode.dark.brightnessFor(Brightness.light), Brightness.dark);
  });

  test('a choice survives a reload', () async {
    await ThemeModeController().setMode(AppThemeMode.dark);

    final reloaded = ThemeModeController();
    await reloaded.load();

    expect(reloaded.mode, AppThemeMode.dark);
  });

  test('reads back nothing when nothing was written', () async {
    final store = ThemeModeController();
    await store.load();

    expect(store.mode, AppThemeMode.system);
  });

  test('a value it does not recognise is treated as nothing saved', () async {
    // Storage is shared with whatever an older build wrote there.
    await SharedPreferencesAsync().setString(ThemeModeControllerBase.storageKey, 'sepia');

    final store = ThemeModeController();
    await store.load();

    expect(store.mode, AppThemeMode.system);
  });

  test('a storage that refuses does not stop the mode changing', () async {
    final store = ThemeModeController(preferences: _RefusingPreferences());

    await store.setMode(AppThemeMode.light);
    expect(store.mode, AppThemeMode.light);

    // And a failing read leaves the default standing rather than throwing.
    await store.load();
  });
}

/// A browser in private mode, or with storage disabled.
class _RefusingPreferences implements SharedPreferencesAsync {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(StateError('storage refused'));
}
