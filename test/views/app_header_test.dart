import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/theme_mode_controller.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_logo.dart';
import 'package:i_can_code/views/components/settings_menu.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// The test surface's own width. A host sized wider is silently clipped, which
/// reads as a layout bug that is not there.
const double _width = 800;

Widget _host(Widget child) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(_width, 800)),
        // A Navigator, not a bare Overlay: `showFDialog` looks one up, and the
        // Navigator brings the Overlay the popover menu needs.
        child: Navigator(
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, _, _) =>
                Align(alignment: Alignment.topCenter, child: SizedBox(width: _width, child: child)),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    GetIt.I
      ..registerSingleton<LocaleController>(LocaleController())
      // The cog's light/dark group reads it.
      ..registerSingleton<ThemeModeController>(ThemeModeController())
      // The cog reads it to decide whether to offer "reset progress".
      ..registerSingleton<ProgressStore>(ProgressStore());
  });

  tearDown(GetIt.I.reset);

  testWidgets('the cog sits against the right edge', (tester) async {
    await tester.pumpWidget(_host(const AppHeader()));
    await tester.pumpAndSettle();

    // 32px of header padding and nothing else between it and the edge. A second
    // flexible child would share the free space and leave its unused half after
    // the cog.
    expect(tester.getBottomRight(find.byType(SettingsMenu)).dx, _width - 32);
  });

  testWidgets('trailing content sits immediately left of the cog', (tester) async {
    await tester.pumpWidget(
      _host(const AppHeader(trailing: SizedBox(width: 70, height: 28, key: ValueKey('bar')))),
    );
    await tester.pumpAndSettle();

    final trailingRight = tester.getBottomRight(find.byKey(const ValueKey('bar'))).dx;
    final cogLeft = tester.getTopLeft(find.byType(SettingsMenu)).dx;

    expect(cogLeft - trailingRight, 20, reason: 'the gap the header states, and nothing more');
  });

  testWidgets('the trail starts at the app and reads left to right', (tester) async {
    await tester.pumpWidget(
      _host(
        AppHeader(
          onTapHome: () {},
          crumbs: [const AppCrumb('Python'), AppCrumb('Invoer en uitvoer', onTap: () {})],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('I Can Code'), findsOneWidget);
    expect(find.text('Python'), findsOneWidget);
    expect(find.text('Invoer en uitvoer'), findsOneWidget);

    final x = [
      tester.getTopLeft(find.text('I Can Code')).dx,
      tester.getTopLeft(find.text('Python')).dx,
      tester.getTopLeft(find.text('Invoer en uitvoer')).dx,
    ];
    expect(x, orderedEquals([...x]..sort()), reason: 'app first, then language, then lesson');
  });

  testWidgets('the trail sits against the logo, not out by the cog', (tester) async {
    await tester.pumpWidget(
      _host(AppHeader(onTapHome: () {}, crumbs: const [AppCrumb('Python')])),
    );
    await tester.pumpAndSettle();

    // Measured against the logo rather than against a number, because
    // FBreadcrumb adds a little padding of its own to the first crumb.
    final logoRight = tester.getBottomRight(find.byType(AppLogo)).dx;
    final trailLeft = tester.getTopLeft(find.text('I Can Code')).dx;

    expect(trailLeft - logoRight, lessThan(24), reason: 'the trail hugs the logo');
    expect(trailLeft, lessThan(_width / 2), reason: 'and is nowhere near the cog');
  });

  testWidgets('the app crumb goes home', (tester) async {
    var home = 0;
    await tester.pumpWidget(_host(AppHeader(onTapHome: () => home++, crumbs: const [AppCrumb('Python')])));
    await tester.pumpAndSettle();

    await tester.tap(find.text('I Can Code'));
    await tester.pumpAndSettle();

    expect(home, 1);
  });

  testWidgets('the cog opens the settings menu', (tester) async {
    await tester.pumpWidget(_host(const AppHeader()));
    await tester.pumpAndSettle();

    expect(find.text('Nederlands'), findsNothing);

    await tester.tap(find.byType(SettingsMenu));
    await tester.pumpAndSettle();

    // FPopover.defaultBuilder returns the child untouched, so the popover adds
    // no gesture of its own and something must call the controller.
    expect(find.text('Nederlands'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    // Nothing done yet, so there is nothing to offer to clear.
    expect(find.text('Voortgang wissen'), findsNothing);
  });

  testWidgets('reset is offered once there is progress, and asks first', (tester) async {
    final lesson = CourseLesson(
      entry: const LessonEntry(language: 'python', order: 1, slug: 'intro', paths: {'nl': 'x'}),
      translations: {
        'nl': const Lesson(
          id: 'intro',
          title: 'T',
          sections: [LessonSection(id: 'a', title: 'A', kind: SectionKind.info, prose: '')],
        ),
      },
    );
    await GetIt.I<ProgressStore>().markFinished(lesson, 'a');

    await tester.pumpWidget(_host(const AppHeader()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SettingsMenu));
    await tester.pumpAndSettle();

    expect(find.text('Voortgang wissen'), findsOneWidget);

    await tester.tap(find.text('Voortgang wissen'));
    await tester.pumpAndSettle();

    // Irreversible, so it asks, and backing out leaves the ticks alone.
    expect(find.text('Voortgang wissen?'), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(GetIt.I<ProgressStore>().hasProgress, isTrue);

    await tester.tap(find.byType(SettingsMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voortgang wissen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wissen'));
    await tester.pumpAndSettle();

    expect(GetIt.I<ProgressStore>().hasProgress, isFalse);
  });

  testWidgets('choosing a language switches it and closes the menu', (tester) async {
    await tester.pumpWidget(_host(const AppHeader()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SettingsMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(GetIt.I<LocaleController>().locale, const Locale('en'));
    expect(find.text('Nederlands'), findsNothing);
  });

  testWidgets('following the device is offered alongside the languages', (tester) async {
    await tester.pumpWidget(_host(const AppHeader()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SettingsMenu));
    await tester.pumpAndSettle();

    expect(find.text('Apparaattaal'), findsOneWidget);

    // Off the device first, or the tap below would be a no-op — following the
    // device is where the app already starts.
    await tester.tap(find.text('Nederlands'));
    await tester.pumpAndSettle();
    expect(GetIt.I<LocaleController>().followsDevice, isFalse);

    await tester.tap(find.byType(SettingsMenu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apparaattaal'));
    await tester.pumpAndSettle();

    // Null, not a locale: `WidgetsApp` is what resolves the device's languages
    // against the supported ones.
    expect(GetIt.I<LocaleController>().locale, isNull);
    expect(GetIt.I<LocaleController>().followsDevice, isTrue);
  });
}
