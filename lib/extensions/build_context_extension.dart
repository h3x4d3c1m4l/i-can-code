import 'package:flutter/widgets.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';

extension BuildContextExtension on BuildContext {

  NavigatorState get navigator => Navigator.of(this);
  NavigatorState get rootNavigator => Navigator.of(this, rootNavigator: true);

  AppLocalizations get localizations => AppLocalizations.of(this)!;

}
