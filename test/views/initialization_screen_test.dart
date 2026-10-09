import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/services/bootstrap_status.dart';
import 'package:i_can_code/services/mobile_browser_warning.dart';
import 'package:i_can_code/services/pending_navigation_service.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/tour_store.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const Locale _locale = Locale('nl');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final continueLabel = lookupAppLocalizations(_locale).initializationScreen_mobileContinue;

  // The real faces, because the test font is far wider than they are and
  // would overflow a phone that the app fits on.
  setUpAll(() async {
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    for (final family in manifest.cast<Map<String, dynamic>>()) {
      if (family['family'] != kBodyFontFamily && family['family'] != kDisplayFontFamily) continue;

      final loader = FontLoader(family['family'] as String);
      for (final font in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    // A bundle with nothing in it, so the bootstrap loads an empty course
    // rather than whichever one this checkout happens to hold.
    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async => utf8.decode(message!.buffer.asUint8List()) == 'AssetManifest.bin'
          ? const StandardMessageCodec().encodeMessage(<String, Object>{})
          : null,
    );
  });

  tearDown(GetIt.I.reset);

  testWidgets('a mobile browser is warned before the app opens, and can go on', (tester) async {
    _register(applies: true);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text(continueLabel), findsOneWidget);
    expect(find.byType(SubjectsScreen), findsNothing);
    expect(GetIt.I<BootstrapStatus>().completed, isFalse, reason: 'no address may get past the warning');

    await tester.tap(find.text(continueLabel));
    await tester.pumpAndSettle();

    expect(find.byType(SubjectsScreen), findsOneWidget);
    expect(GetIt.I<BootstrapStatus>().completed, isTrue);

    final reloaded = MobileBrowserWarning(applies: true);
    await reloaded.load();
    expect(reloaded.due, isFalse, reason: 'this browser is not asked again');
  });

  testWidgets('a browser that already went on is not asked again', (tester) async {
    await MobileBrowserWarning(applies: true).dismiss();
    _register(applies: true);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text(continueLabel), findsNothing);
    expect(find.byType(SubjectsScreen), findsOneWidget);
  });

  testWidgets('anything but a mobile browser opens without a warning', (tester) async {
    _register(applies: false);

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text(continueLabel), findsNothing);
    expect(find.byType(SubjectsScreen), findsOneWidget);
  });

  for (final size in const [Size(320, 568), Size(568, 320)]) {
    testWidgets('the warning fits a phone of ${size.width.toInt()} by ${size.height.toInt()}', (tester) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      _register(applies: true);

      // An overflow anywhere on the screen fails the test by itself.
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(continueLabel));
      await tester.pumpAndSettle();

      expect(find.text(continueLabel).hitTestable(), findsOneWidget, reason: 'the way on has to be reachable');
    });
  }
}

/// What `setupServices()` registers, as far as the bootstrap and the first
/// screen read it.
void _register({required bool applies}) {
  GetIt.I
    ..registerSingleton<BootstrapStatus>(BootstrapStatus())
    ..registerSingleton<PendingNavigationService>(PendingNavigationService())
    ..registerSingleton<ProgressStore>(ProgressStore())
    ..registerSingleton<CodeDraftStore>(CodeDraftStore())
    ..registerSingleton<TourStore>(TourStore())
    ..registerSingleton<MobileBrowserWarning>(MobileBrowserWarning(applies: applies));
}

/// The app's own router with nothing above it but a theme, so the guard and
/// the initialization screen run the way they do in the shell.
Widget _app() => WidgetsApp.router(
  color: const Color(0xFF000000),
  locale: _locale,
  routerConfig: AppRouter().config(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => FTheme(data: buildAppTheme(), child: child!),
);
