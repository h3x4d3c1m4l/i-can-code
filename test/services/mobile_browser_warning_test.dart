import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/mobile_browser_warning.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  test('a phone or a tablet counts only in a browser', () {
    for (final platform in TargetPlatform.values) {
      final mobile = platform == TargetPlatform.iOS || platform == TargetPlatform.android;

      expect(isMobileBrowser(isWeb: true, platform: platform), mobile, reason: '$platform in a browser');
      // A native build has the same platform and none of the editor's trouble.
      expect(isMobileBrowser(isWeb: false, platform: platform), isFalse, reason: '$platform as a native build');
    }
  });

  test('the warning is due until the reader goes on, and that is remembered', () async {
    final warning = MobileBrowserWarning(applies: true);
    await warning.load();
    expect(warning.due, isTrue);

    await warning.dismiss();
    expect(warning.due, isFalse);

    final reloaded = MobileBrowserWarning(applies: true);
    expect(reloaded.due, isTrue, reason: 'nothing is read before load');

    await reloaded.load();
    expect(reloaded.due, isFalse);
  });

  test('forgetting the choice makes the warning due again', () async {
    await MobileBrowserWarning(applies: true).dismiss();

    final warning = MobileBrowserWarning(applies: true);
    await warning.load();
    await warning.clear();
    expect(warning.due, isTrue);

    final reloaded = MobileBrowserWarning(applies: true);
    await reloaded.load();
    expect(reloaded.due, isTrue);
  });

  test('nothing is due where the warning does not apply', () async {
    final warning = MobileBrowserWarning(applies: false);
    await warning.load();

    expect(warning.due, isFalse);
  });
}
