import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/licenses/bundled_licenses.dart';
import 'package:i_can_code/services/licenses/license_catalog.dart';

/// What the list calls [origin].
///
/// A name is the same word in every language, so only the origins that are not
/// one are translated.
String originLabel(AppLocalizations localizations, LicenseOrigin origin) => switch (origin) {
  LicenseOrigin.app => localizations.licensesScreen_originApp,
  LicenseOrigin.python => 'Python',
  LicenseOrigin.tkinter => 'Tkinter',
  LicenseOrigin.rust => 'Rust',
  LicenseOrigin.microbit => 'micro:bit',
  LicenseOrigin.fonts => localizations.licensesScreen_originFonts,
  LicenseOrigin.other => localizations.licensesScreen_originOther,
  LicenseOrigin.packages => 'Dart & Flutter',
};

/// What the screen calls [component]: its own name, except for the app, which
/// the registry knows by its package name and a reader by its title.
String componentName(AppLocalizations localizations, LicensedComponent component) =>
    component.origin == LicenseOrigin.app ? localizations.app_title : component.name;

/// The components of [catalog] whose name holds [query], by origin and in the
/// catalog's own order. An origin with none left is left out.
Map<LicenseOrigin, List<LicensedComponent>> groupsMatching(
  LicenseCatalog catalog,
  String query,
  AppLocalizations localizations,
) {
  final needle = query.trim().toLowerCase();
  final groups = <LicenseOrigin, List<LicensedComponent>>{};

  for (final component in catalog.components) {
    if (needle.isNotEmpty && !componentName(localizations, component).toLowerCase().contains(needle)) continue;
    groups.putIfAbsent(component.origin, () => []).add(component);
  }
  return groups;
}
