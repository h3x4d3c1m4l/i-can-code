import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// The Sentry DSN this build was given, or empty for a build that reports
/// nothing.
///
/// Only the course repository's deploy passes one, so `flutter run`, the tests
/// and the GitHub Pages copy never load Sentry at all.
const String _dsn = String.fromEnvironment('SENTRY_DSN');

/// Whether this build sends its errors to Sentry.
const bool kReportsErrors = _dsn != '';

/// How long the first frame waits for Sentry before starting without it.
///
/// On the web the SDK loads its JavaScript half from Sentry's CDN and has no
/// timeout of its own, so a network that drops those requests would otherwise
/// hold the app on its splash screen.
const Duration _sdkWaitLimit = Duration(seconds: 3);

/// Runs [start] inside Sentry's error zone when this build reports errors, and
/// as it is otherwise.
///
/// [start] MUST create the binding and call `runApp` itself: on the web the
/// binding has to be created in the zone the app runs in, or Flutter reports a
/// zone mismatch. See "Zone Mismatch Error on Web" in
/// https://docs.sentry.io/platforms/dart/guides/flutter/troubleshooting/.
Future<void> runReportingErrors(Future<void> Function() start) async {
  if (!kReportsErrors) return start();

  await Sentry.runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Future.any([_initSentry(), Future<void>.delayed(_sdkWaitLimit)]);
      await start();
    },
    // Sentry has already captured it.
    (_, _) {},
  );
}

Future<void> _initSentry() async {
  try {
    await SentryFlutter.init((options) {
      options
        ..dsn = _dsn
        // Errors and sessions only. A transaction per screen would send every
        // student's route through the course to Sentry.
        ..tracesSampleRate = null;
    });
  } on Object catch (error) {
    // A malformed DSN throws here. The app MUST still start.
    debugPrint('Sentry did not start: $error');
  }
}

/// Wraps the app in what Sentry needs above it, when this build reports errors.
Widget withErrorReporting(Widget app) => kReportsErrors ? SentryWidget(child: app) : app;

/// Sends a panic in the Rust core to Sentry, when this build reports errors.
///
/// The JavaScript SDK already reports the trap that follows a panic, as
/// `RuntimeError: unreachable` with nothing but wasm offsets. This event is the
/// one that says what went wrong, with the app's breadcrumbs beside it.
void reportCorePanic(String message, {String? location}) {
  if (!kReportsErrors) return;

  unawaited(
    Sentry.captureEvent(
      SentryEvent(
        level: SentryLevel.fatal,
        exceptions: [
          SentryException(
            // Stated rather than taken from a Dart type, whose name is minified on the web.
            type: 'RustPanic',
            value: message,
            mechanism: Mechanism(type: 'rust_panic', handled: false),
          ),
        ],
        tags: {'rust.location': ?location},
        // One issue per panic site: the message may carry the values involved.
        fingerprint: ['rust-panic', location ?? message],
      ),
    ),
  );
}

/// The navigator observers the router MUST be given.
///
/// On the web Sentry only tracks sessions once its observer exists, so release
/// health depends on it.
List<NavigatorObserver> errorReportingObservers() => [
  if (kReportsErrors) SentryNavigatorObserver(enableAutoTransactions: false),
];
