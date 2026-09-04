import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/app_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

PackageInfo _info(String version) =>
    PackageInfo(appName: 'I Can Code', packageName: 'i_can_code', version: version, buildNumber: '1');

void main() {
  tearDown(GetIt.I.reset);

  test('there is no version to show when nothing was registered', () {
    // A widget test builds a screen without main() ever running, and must not
    // trip over GetIt for a string this cosmetic.
    expect(appVersion, isNull);
  });

  test('there is no version to show when the build could not report one', () {
    // Empty strings are what the web plugin answers with when it cannot find
    // version.json — it does not throw.
    GetIt.I.registerSingleton(PackageInfo(appName: '', packageName: '', version: '', buildNumber: ''));

    expect(appVersion, isNull);
  });

  test('the version is the one the build reports, without its build number', () {
    GetIt.I.registerSingleton(_info('0.1.0'));

    expect(appVersion, '0.1.0');
  });

  test('a build whose metadata cannot be read still starts', () async {
    // No plugin behind the method channel under flutter_test, so this is the
    // failure path. It MUST be swallowed rather than taking main() down.
    await loadPackageInfo();

    expect(appVersion, isNull);
  });
}
