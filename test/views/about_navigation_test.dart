import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/services/bootstrap_status.dart';
import 'package:i_can_code/services/color_vision_controller.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/services/mobile_browser_warning.dart';
import 'package:i_can_code/services/pending_navigation_service.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/services/startup_progress/startup_progress.dart';
import 'package:i_can_code/services/theme_mode_controller.dart';
import 'package:i_can_code/services/tour_store.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/about_screen/about_screen.dart';
import 'package:i_can_code/views/components/app_header_host.dart';
import 'package:i_can_code/views/components/settings_menu.dart';
import 'package:i_can_code/views/licenses_screen/licenses_screen.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    // A bundle holding a course with no lessons in it, so the bootstrap loads
    // that rather than whichever one this checkout happens to hold.
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async => utf8.decode(message!.buffer.asUint8List()) == Course.bundleAsset
          ? ByteData.sublistView(utf8.encode('{}'))
          : null,
    );

    GetIt.I
      ..registerSingleton<AppRouter>(AppRouter())
      ..registerSingleton<BootstrapStatus>(BootstrapStatus())
      ..registerSingleton<PendingNavigationService>(PendingNavigationService())
      ..registerSingleton<LocaleController>(LocaleController())
      ..registerSingleton<ThemeModeController>(ThemeModeController())
      ..registerSingleton<ColorVisionController>(ColorVisionController())
      ..registerSingleton<FeatureToggles>(FeatureToggles())
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<CodeDraftStore>(CodeDraftStore())
      ..registerSingleton<TourStore>(TourStore())
      ..registerSingleton<MobileBrowserWarning>(MobileBrowserWarning(applies: false))
      ..registerSingleton<StartupProgress>(StartupProgress())
      // About asks the interpreter its version, which the stub cannot give.
      ..registerSingleton<PythonRuntime>(createPythonRuntime());
  });

  tearDown(GetIt.I.reset);

  testWidgets('the cog opens About on top of the screen it was pressed on', (tester) async {
    await _pumpShell(tester);
    expect(find.byType(SubjectsScreen), findsOneWidget);

    await _openAboutFromCog(tester);

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(GetIt.I<AppRouter>().currentPath, '/about');
    // Pushed, not replaced: Back has the screen under it to return to.
    expect(GetIt.I<AppRouter>().stack, hasLength(2));

    // A second press from About itself must not stack another copy.
    await _openAboutFromCog(tester);

    expect(GetIt.I<AppRouter>().stack, hasLength(2));

    GetIt.I<AppRouter>().back();
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsNothing);
    expect(find.byType(SubjectsScreen), findsOneWidget);
  });

  testWidgets('About opens the licences, and their crumb leads back to it', (tester) async {
    await _pumpShell(tester);
    await _openAboutFromCog(tester);

    await tester.tap(find.text('Licenties'));
    await tester.pumpAndSettle();

    expect(find.byType(LicensesScreen), findsOneWidget);
    expect(GetIt.I<AppRouter>().currentPath, '/licenses');
    expect(GetIt.I<AppRouter>().stack, hasLength(3));

    // Popped back to, not pushed again: Back from About still reaches home.
    await tester.tap(find.text('Over deze app'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(GetIt.I<AppRouter>().stack, hasLength(2));
  });
}

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_shell());
  await tester.pumpAndSettle();
}

Future<void> _openAboutFromCog(WidgetTester tester) async {
  await tester.tap(find.byType(SettingsMenu));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FItem, 'Over deze app'));
  await tester.pumpAndSettle();
}

/// The router under the bar's host, the way `ICanCodeApp` builds them: the cog
/// is above the router and has to reach it all the same.
Widget _shell() => WidgetsApp.router(
  color: const Color(0xFF000000),
  locale: const Locale('nl'),
  routerConfig: GetIt.I<AppRouter>().config(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => FTheme(
    data: buildAppTheme(),
    child: AppHeaderHost(child: child!),
  ),
);
