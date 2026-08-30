import 'dart:ui';

import 'package:mobx/mobx.dart';

part 'locale_controller.g.dart';

class LocaleController = LocaleControllerBase with _$LocaleController;

/// The app's language, switched from the header's NL/EN toggle. Not persisted,
/// so a reload lands back on Dutch — the default, because the course is taught
/// in Dutch and following the device locale would misplace most students.
abstract class LocaleControllerBase with Store {

  static const List<Locale> supported = [Locale('nl'), Locale('en')];

  @readonly
  Locale _locale = const Locale('nl');

  @action
  void setLocale(Locale locale) => _locale = locale;

}
