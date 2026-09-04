import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads the running build's own metadata and registers it, so a screen can ask
/// for it without waiting on anything.
///
/// Awaited by `main()` beside the theme and locale controllers, and it swallows
/// its own failure exactly as they do: this is one short string on one screen,
/// so a build that cannot report its version MUST still start. That is also why
/// it is not a step of the initialization screen, whose failures are fatal.
///
/// On the web the plugin fetches the `version.json` that the build writes beside
/// `index.html` — same origin, so cross-origin isolation does not touch it. It
/// does **not** throw when that file is missing; it answers with empty strings,
/// which [appVersion] reads as "nothing to show".
Future<void> loadPackageInfo() async {
  try {
    GetIt.I.registerSingleton<PackageInfo>(await PackageInfo.fromPlatform());
  } on Object {
    // Deliberately silent: see above. Nothing is registered, and [appVersion]
    // answers null.
  }
}

/// The app's own version, the one the bar shows beside the mark on the home
/// screen — or null when there is none to show.
///
/// Null covers a build that could not report its metadata *and* a widget test
/// that never registered any, so no caller has to null-check GetIt for a string
/// this cosmetic.
///
/// The build number is deliberately left off: `+1` says nothing to a student.
String? get appVersion {
  if (!GetIt.I.isRegistered<PackageInfo>()) return null;

  final version = GetIt.I<PackageInfo>().version;
  return version.isEmpty ? null : version;
}
