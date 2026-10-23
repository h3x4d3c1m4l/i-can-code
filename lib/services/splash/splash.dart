// Only the web page has a splash. Everything else, the Dart VM a `flutter test`
// runs on included, falls through to the stub.
//
// A conditional import resolves the URI of whichever clause matches, so a clause
// MUST NOT be added before the file it names exists: on the VM the missing file
// would be a compile error for every test that reaches this library.
import 'package:i_can_code/services/splash/splash_stub.dart'
    if (dart.library.js_interop) 'package:i_can_code/services/splash/splash_web.dart'
    as impl;

/// Takes the splash `web/index.html` draws out of the page.
///
/// The page leaves it standing under the app, because the app's first frame
/// reaches the screen well after `runApp()` returns, and until it does the
/// splash is what shows through. So this MUST NOT be called before the app has
/// been on screen for a while. Does nothing where there is no splash, or once it
/// is gone.
void removeSplash() => impl.removeSplash();
