import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
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
import 'package:i_can_code/views/components/app_header_host.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';
import 'package:i_can_code/views/components/settings_menu.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Marks the screen under the bar, so its top edge can be measured.
const Key _screenKey = ValueKey('screen');

/// Nothing above the host, the way the app shell has nothing above it: the
/// Overlay and Navigator the bar's own cog needs are the host's to bring.
Widget _host(ValueListenable<Widget> screen) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: AppHeaderHost(
          child: ValueListenableBuilder<Widget>(
            valueListenable: screen,
            builder: (_, child, _) => child,
          ),
        ),
      ),
    ),
  ),
);

/// The bar with a real page stack under it: one screen pushed over another, the
/// way the catalog goes over the language picker.
Widget _stackedHost(GlobalKey<NavigatorState> pages) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: AppHeaderHost(
          child: Navigator(
            key: pages,
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => _screen(crumbs: const [AppCrumb('Python')]),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// A screen that publishes a header and fills whatever it is given.
Widget _screen({List<AppCrumb> crumbs = const [], bool zen = false, Key? key}) => AppHeaderPublisher(
  key: key,
  builder: (context) => AppHeaderConfig(crumbs: crumbs, onTapHome: () {}, offersZen: zen),
  child: const SizedBox.expand(key: _screenKey),
);

double _topOf(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

/// Every label in the live semantics tree.
///
/// Not `find.bySemanticsLabel`, which reads a render object's own annotation
/// and so still finds a widget an [ExcludeSemantics] above it has dropped.
Set<String> _semanticLabels(WidgetTester tester) {
  final labels = <String>{};

  void walk(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // The host carries no semantics of its own, so this resolves to the node
  // above it — the root of the tree the app renders into.
  walk(tester.getSemantics(find.byType(AppHeaderHost)));
  return labels;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    GetIt.I
      ..registerSingleton<LocaleController>(LocaleController())
      ..registerSingleton<ThemeModeController>(ThemeModeController())
      ..registerSingleton<ProgressStore>(ProgressStore());
  });

  tearDown(GetIt.I.reset);

  testWidgets('a screen fills the bar, and lies under it', (tester) async {
    final screen = ValueNotifier<Widget>(_screen(crumbs: const [AppCrumb('Python')]));
    addTearDown(screen.dispose);

    await tester.pumpWidget(_host(screen));
    await tester.pumpAndSettle();

    expect(find.text('Python'), findsOneWidget);
    expect(_topOf(tester, find.byType(AppHeader)), 0);
    // The whole window, with the bar drawn over the top of it: what keeps a
    // screen's first screenful clear of the bar is its own top padding.
    expect(tester.getRect(find.byKey(_screenKey)), tester.getRect(find.byType(AppHeaderHost)));
  });

  testWidgets('navigating swaps the trail without replacing the bar', (tester) async {
    final screen = ValueNotifier<Widget>(
      _screen(crumbs: const [AppCrumb('Python')], key: const ValueKey('a')),
    );
    addTearDown(screen.dispose);

    await tester.pumpWidget(_host(screen));
    await tester.pumpAndSettle();

    // The bar is one widget for the life of the app, so everything it holds —
    // the popover the cog owns included — survives a screen it outlives.
    final cog = tester.state(find.byType(SettingsMenu));

    screen.value = _screen(
      crumbs: const [AppCrumb('Python'), AppCrumb('Invoer en uitvoer')],
      key: const ValueKey('b'),
    );
    await tester.pumpAndSettle();

    expect(tester.state(find.byType(SettingsMenu)), same(cog));
    // The screen arriving publishes before the one leaving releases, and a
    // release by an owner that no longer fills the bar is ignored — otherwise
    // this trail would be empty.
    expect(find.text('Invoer en uitvoer'), findsOneWidget);
  });

  testWidgets('the trail fades out before the new one fades in', (tester) async {
    final screen = ValueNotifier<Widget>(
      _screen(crumbs: const [AppCrumb('Python')], key: const ValueKey('a')),
    );
    addTearDown(screen.dispose);

    await tester.pumpWidget(_host(screen));
    await tester.pumpAndSettle();

    screen.value = _screen(crumbs: const [AppCrumb('Ruby')], key: const ValueKey('b'));
    // Twice: the first frame is where the screen publishes, the second is where
    // the bar rebuilds and the swap starts.
    await tester.pump();
    await tester.pump();
    // Just short of the changeover, where the old one has faded out and the new
    // one has not started. A crossfade would have both half showing here.
    await tester.pump(const Duration(milliseconds: 120));

    final fades = tester.widgetList<FadeTransition>(
      find.descendant(of: find.byType(AppHeader), matching: find.byType(FadeTransition)),
    );
    expect(fades.length, 2, reason: 'the trail leaving and the trail arriving');
    expect(fades.every((fade) => fade.opacity.value < 0.05), isTrue);

    await tester.pumpAndSettle();
    expect(find.text('Python'), findsNothing);
    expect(find.text('Ruby'), findsOneWidget);
  });

  testWidgets('leaving a screen hands the bar back to the one underneath', (tester) async {
    final pages = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_stackedHost(pages));
    await tester.pumpAndSettle();

    unawaited(pages.currentState!.push<void>(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => _screen(crumbs: const [AppCrumb('Python'), AppCrumb('Invoer')]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Invoer'), findsOneWidget);

    pages.currentState!.pop();
    await tester.pumpAndSettle();

    // The screen underneath never left, so nothing publishes on the way back:
    // the bar has to fall back to it on its own.
    expect(find.text('Invoer'), findsNothing);
    expect(find.text('Python'), findsOneWidget);
  });


  group('the cog, with nothing above the bar to hang off', () {
    testWidgets('opens its menu, and past the bar it stands in', (tester) async {
      final screen = ValueNotifier<Widget>(_screen(crumbs: const [AppCrumb('Python')]));
      addTearDown(screen.dispose);

      await tester.pumpWidget(_host(screen));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SettingsMenu));
      await tester.pumpAndSettle();

      // An OverlayPortal with no Overlay above it throws, and the error widget
      // that replaces the cog is wide enough to squeeze the trail out of the row.
      expect(tester.takeException(), isNull);
      expect(find.text('Nederlands'), findsOneWidget);
      // The overlay it found is the window's, not the bar's: a menu clipped to
      // 76px would end inside the bar.
      expect(tester.getBottomLeft(find.text('Nederlands')).dy, greaterThan(AppHeader.height));
    });

    testWidgets('and opens the dialog that asks before wiping progress', (tester) async {
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

      final screen = ValueNotifier<Widget>(_screen(crumbs: const [AppCrumb('Python')]));
      addTearDown(screen.dispose);

      await tester.pumpWidget(_host(screen));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SettingsMenu));
      await tester.pumpAndSettle();

      // showFDialog looks up a Navigator, which is the other half of what the
      // bar lost by moving above the router.
      await tester.tap(find.text('Voortgang wissen'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Voortgang wissen?'), findsOneWidget);
    });
  });

  group('zen mode', () {
    testWidgets('a lesson opens with the bar away, and the page has the window', (tester) async {
      final screen = ValueNotifier<Widget>(_screen(crumbs: const [AppCrumb('Python')], zen: true));
      addTearDown(screen.dispose);

      await tester.pumpWidget(_host(screen));
      await tester.pumpAndSettle();

      expect(_topOf(tester, find.byType(AppHeader)), -AppHeader.height);
      // The page is never inset for the bar. It keeps the same box whichever
      // way the bar is going, and its content passes under it.
      expect(_topOf(tester, find.byKey(_screenKey)), 0);
    });

    testWidgets('the button brings the bar back without moving the page', (tester) async {
      final semantics = tester.ensureSemantics();
      final screen = ValueNotifier<Widget>(_screen(crumbs: const [AppCrumb('Python')], zen: true));
      addTearDown(screen.dispose);

      await tester.pumpWidget(_host(screen));
      await tester.pumpAndSettle();

      // Without it the bar is not out of the way, it is lost.
      expect(_semanticLabels(tester), contains('Balk tonen'));

      // It waits exactly where the cog will be, so pressing it puts the cog
      // under the pointer.
      final button = tester.getRect(find.bySemanticsLabel('Balk tonen'));
      final page = tester.getRect(find.byKey(_screenKey));

      await tester.tap(find.bySemanticsLabel('Balk tonen'));
      await tester.pumpAndSettle();

      expect(_topOf(tester, find.byType(AppHeader)), 0);
      expect(tester.getRect(find.byKey(_screenKey)), page, reason: 'the page did not move or resize');
      expect(tester.getRect(find.byType(SettingsMenu)), button);
      // Faded out is not gone: it would otherwise still be read out, and still
      // take the click meant for the bar it stood in for.
      expect(_semanticLabels(tester), isNot(contains('Balk tonen')));
      expect(_semanticLabels(tester), contains('Balk verbergen'));
      semantics.dispose();
    });

    testWidgets('the button in the bar puts it away again', (tester) async {
      final semantics = tester.ensureSemantics();
      final screen = ValueNotifier<Widget>(_screen(crumbs: const [AppCrumb('Python')], zen: true));
      addTearDown(screen.dispose);

      await tester.pumpWidget(_host(screen));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Balk tonen'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Balk verbergen'));
      await tester.pumpAndSettle();

      expect(_topOf(tester, find.byType(AppHeader)), -AppHeader.height);
      expect(_topOf(tester, find.byKey(_screenKey)), 0, reason: 'still not moving');
      // Nothing left of the bar to reach with a tab, either.
      expect(_semanticLabels(tester), isNot(contains('Instellingen')));
      semantics.dispose();
    });

    testWidgets('the next lesson opens without the bar all the same', (tester) async {
      final screen = ValueNotifier<Widget>(
        _screen(crumbs: const [AppCrumb('Python')], zen: true, key: const ValueKey('a')),
      );
      addTearDown(screen.dispose);

      await tester.pumpWidget(_host(screen));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Balk tonen'));
      await tester.pumpAndSettle();

      screen.value = _screen(crumbs: const [AppCrumb('Ruby')], zen: true, key: const ValueKey('b'));
      await tester.pumpAndSettle();

      // Asking for the bar was about the lesson being read, not about every
      // lesson after it.
      expect(_topOf(tester, find.byType(AppHeader)), -AppHeader.height);
    });

    testWidgets('a screen that does not offer zen carries neither button', (tester) async {
      final semantics = tester.ensureSemantics();
      final screen = ValueNotifier<Widget>(_screen(crumbs: const [AppCrumb('Python')]));
      addTearDown(screen.dispose);

      await tester.pumpWidget(_host(screen));
      await tester.pumpAndSettle();

      expect(_semanticLabels(tester), isNot(contains('Balk verbergen')));
      expect(_semanticLabels(tester), isNot(contains('Balk tonen')));
      expect(_topOf(tester, find.byType(AppHeader)), 0);
      semantics.dispose();
    });
  });
}
