import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('starts by following the device', () {
    // Null, not a locale: `WidgetsApp` is what resolves the device's languages
    // against the supported ones.
    expect(LocaleController().locale, isNull);
    expect(LocaleController().followsDevice, isTrue);
  });

  test('Dutch is the fallback the framework resolves to', () {
    // `WidgetsApp` lands on the first supported locale when it has none of the
    // device's, so the order of this list is load-bearing: it is what keeps a
    // device set to, say, French on the course's own language.
    expect(LocaleControllerBase.supported.first, const Locale('nl'));
  });

  test('a chosen language survives a reload', () async {
    await LocaleController().setLocale(const Locale('en'));

    final reloaded = LocaleController();
    await reloaded.load();

    expect(reloaded.locale, const Locale('en'));
    expect(reloaded.followsDevice, isFalse);
  });

  test('following the device survives a reload', () async {
    // Stored as a sentinel rather than by clearing the key, so that it is a
    // choice like any other rather than indistinguishable from never having
    // picked.
    await LocaleController().setLocale(null);

    final reloaded = LocaleController();
    await reloaded.load();

    expect(reloaded.locale, isNull);
    expect(reloaded.followsDevice, isTrue);
  });

  test('reads back the default when nothing was written', () async {
    final store = LocaleController();
    await store.load();

    expect(store.locale, isNull);
  });

  test('a language the app no longer ships falls back to the device', () async {
    // Storage is shared with whatever an older build wrote there. A dropped
    // language leaves the student where someone who never picked would be.
    await SharedPreferencesAsync().setString(LocaleControllerBase.storageKey, 'fr');

    final store = LocaleController();
    await store.load();

    expect(store.locale, isNull);
    expect(store.followsDevice, isTrue);
  });

  test('a storage that refuses does not stop the language changing', () async {
    final store = LocaleController(preferences: _RefusingPreferences());

    await store.setLocale(const Locale('en'));
    expect(store.locale, const Locale('en'));

    // And a failing read leaves the default standing rather than throwing.
    await store.load();
  });
}

/// A browser in private mode, or with storage disabled.
class _RefusingPreferences implements SharedPreferencesAsync {

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(StateError('storage refused'));

}
