/// Stands in where no page is counting its downloads — every platform but the
/// web, the Dart VM a `flutter test` runs on included.
double? readStartupFraction() => null;

/// Never calls [listener]: there is nothing here that could change.
void onStartupFraction(void Function(double fraction) listener) {}
