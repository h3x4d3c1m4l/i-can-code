import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Stands in for the platform's URL launcher and keeps what it was asked to
/// open, in order.
class RecordingUrlLauncher extends UrlLauncherPlatform {

  final launched = <String>[];

  /// Puts a launcher in the platform's place for the running test, and the
  /// platform's own back when that test ends.
  static RecordingUrlLauncher install() {
    final launcher = RecordingUrlLauncher();
    final previous = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    return launcher;
  }

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }

}
