import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/theme_mode_controller.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/settings_menu.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// The last theme the tree was built with, captured on every build.
FThemeData? _painted;

/// The shell's arrangement, cut down to what decides the brightness: an
/// [Observer] that reads the mode inside a build, below a [MediaQuery] that
/// carries the platform's own brightness.
///
/// Deliberately a copy of `_ThemedBody` rather than a call into it — the point
/// is to prove the wiring, and the private widget cannot be reached from here.
Widget _host(Widget child, {Brightness platform = Brightness.light}) => MediaQuery(
  data: MediaQueryData(size: const Size(800, 800), platformBrightness: platform),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Observer(
        builder: (context) {
          final brightness = GetIt.I<ThemeModeController>().mode.brightnessFor(
            MediaQuery.platformBrightnessOf(context),
          );
          final theme = buildAppTheme(brightness: brightness);
          _painted = theme;

          return FTheme(
            data: theme,
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => Align(alignment: Alignment.topRight, child: child),
              ),
            ),
          );
        },
      ),
    ),
  ),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    _painted = null;
    GetIt.I
      ..registerSingleton<LocaleController>(LocaleController())
      ..registerSingleton<ThemeModeController>(ThemeModeController())
      ..registerSingleton<ProgressStore>(ProgressStore());
  });

  tearDown(GetIt.I.reset);

  testWidgets('the cog offers all three modes', (tester) async {
    await tester.pumpWidget(_host(const SettingsMenu()));
    await tester.tap(find.byType(SettingsMenu));
    await tester.pumpAndSettle();

    expect(find.text('Systeem'), findsOneWidget);
    expect(find.text('Licht'), findsOneWidget);
    expect(find.text('Donker'), findsOneWidget);
  });

  testWidgets('picking dark repaints the tree in dark', (tester) async {
    await tester.pumpWidget(_host(const SettingsMenu()));
    expect(_painted!.colors.brightness, Brightness.light);

    await tester.tap(find.byType(SettingsMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Donker'));
    await tester.pumpAndSettle();

    expect(GetIt.I<ThemeModeController>().mode, AppThemeMode.dark);
    expect(_painted!.colors.brightness, Brightness.dark);
    // The page is genuinely repainted, not merely relabelled.
    expect(_painted!.colors.background, buildAppTheme(brightness: Brightness.dark).colors.background);
  });

  testWidgets('system follows the platform', (tester) async {
    await tester.pumpWidget(_host(const SettingsMenu(), platform: Brightness.dark));

    expect(GetIt.I<ThemeModeController>().mode, AppThemeMode.system);
    expect(_painted!.colors.brightness, Brightness.dark);
  });

  testWidgets('an explicit light survives a dark platform', (tester) async {
    await GetIt.I<ThemeModeController>().setMode(AppThemeMode.light);
    await tester.pumpWidget(_host(const SettingsMenu(), platform: Brightness.dark));

    expect(_painted!.colors.brightness, Brightness.light);
  });
}
