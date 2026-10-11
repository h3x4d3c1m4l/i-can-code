import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// What the script in `web/index.html` leaves on `window`, when the build gave
/// it sizes to count against. The name and the event MUST stay in step with it.
@JS('iccStartup')
external _Startup? get _startup;

extension type _Startup._(JSObject _) implements JSObject {

  external double get fraction;

}

const String _changed = 'icc-startup-progress';

/// The share of the startup downloads that has arrived, from 0 to 1, or null
/// when the page is not counting.
double? readStartupFraction() => _startup?.fraction;

/// Calls [listener] with the new share whenever the page reports one. Does
/// nothing when the page is not counting.
///
/// Never stops listening: the store that asks lives as long as the app does,
/// and the page falls silent once everything has arrived.
void onStartupFraction(void Function(double fraction) listener) {
  final startup = _startup;
  if (startup == null) return;

  web.window.addEventListener(_changed, ((web.Event _) => listener(startup.fraction)).toJS);
}
