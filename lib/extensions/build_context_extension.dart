import 'package:flutter/widgets.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';

extension BuildContextExtension on BuildContext {

  NavigatorState get navigator => Navigator.of(this);
  NavigatorState get rootNavigator => Navigator.of(this, rootNavigator: true);

  AppLocalizations get localizations => AppLocalizations.of(this)!;

  /// [duration], or no time at all for a reader who asked for less motion.
  ///
  /// On the web that ask is `prefers-reduced-motion: reduce`, which the engine
  /// maps onto [MediaQueryData.disableAnimations]. A zero duration leaves every
  /// animated widget in place: it still ends where it was going, it just gets
  /// there in one frame.
  Duration motion(Duration duration) => MediaQuery.disableAnimationsOf(this) ? Duration.zero : duration;

}
