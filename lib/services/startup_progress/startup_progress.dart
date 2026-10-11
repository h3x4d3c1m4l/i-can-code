// The page only counts its downloads on the web. Everything else — the Dart VM a
// `flutter test` runs on included — falls through to the stub, which has
// nothing to report.
//
// A conditional import resolves the URI of whichever clause matches, so a clause
// MUST NOT be added before the file it names exists: on the VM the missing file
// would be a compile error for every test that reaches this library.
import 'package:i_can_code/services/startup_progress/startup_progress_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/startup_progress/startup_progress_web.dart'
    as impl;
import 'package:mobx/mobx.dart';

part 'startup_progress.g.dart';

class StartupProgress = StartupProgressBase with _$StartupProgress;

/// How much of what a cold start downloads has arrived.
///
/// The counting is done by the page, not here: a script in `web/index.html`
/// measures every download against sizes the build wrote into it, starting long
/// before the app exists. This is the app's view of that same number, so the
/// initialization screen can carry on the ring the splash was showing.
abstract class StartupProgressBase with Store {

  /// From 0 to 1, or null where nothing is counting: a `flutter run`, whose
  /// page was given no sizes, and every widget test.
  @readonly
  double? _fraction;

  StartupProgressBase() : _fraction = impl.readStartupFraction() {
    impl.onStartupFraction(_set);
  }

  /// A fixed [fraction], for a widget test, which has no page to ask.
  StartupProgressBase.of(double? fraction) : _fraction = fraction;

  @action
  void _set(double fraction) => _fraction = fraction;

}
