import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/services/bootstrap_status.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/services/mobile_browser_warning.dart';
import 'package:i_can_code/services/pending_navigation_service.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/services/startup_progress/startup_progress.dart';
import 'package:i_can_code/services/theme_mode_controller.dart';
import 'package:i_can_code/services/tour_store.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen.dart';
import 'package:i_can_code/views/catalog_screen/components/sticky_group_heading.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_host.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Where a heading stands when an address brought the page to it: in its own
/// spot, right under the bar.
const double _arrived = AppHeader.height + StickyGroupHeading.topGap;

const String _root = 'assets/lessons/python';

/// A lesson of one reading step, with [id] as its title too.
String _lesson(String id) =>
    '# $id\n\n```metadata\nid: $id\nemoji: "🧪"\n```\n\n'
    '## Stap\n\n```metadata\ntype: info\nid: stap\nemoji: "🧪"\n```\n\nTekst.\n';

/// Two weeks of four, which is more than a window of 600 shows at once.
final Map<String, String> _course = {
  '$_root/contents.nl.md': [
    '# Week 1 {#week-1}',
    for (final id in ['a1', 'a2', 'a3', 'a4']) '- [$id]($id.md)',
    '# Week 2 {#week-2}',
    for (final id in ['b1', 'b2', 'b3', 'b4']) '- [$id]($id.md)',
  ].join('\n'),
  for (final id in ['a1', 'a2', 'a3', 'a4', 'b1', 'b2', 'b3', 'b4']) '$_root/$id.md': _lesson(id),
};

ScrollPosition _scroll(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)))
    .position;

/// Tells the app its address changed, the way the browser does when a link is
/// pasted into the address bar of a tab the app is already open in.
Future<void> _visit(WidgetTester tester, String location) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    const JSONMethodCodec().encodeMethodCall(MethodCall('pushRouteInformation', {'location': location, 'state': null})),
    (_) {},
  );
  await tester.pumpAndSettle();
}

/// The router under the bar's host, the way `ICanCodeApp` builds them.
/// [openedAt] is the address the tab was opened on, where that is not `/`.
Widget _shell({String? openedAt}) => WidgetsApp.router(
  color: const Color(0xFF000000),
  locale: const Locale('nl'),
  routerConfig: GetIt.I<AppRouter>().config(
    // auto_route asks `dart:ui` for the first address, which a test cannot
    // set. This is its own door for saying where a start begins. Without the
    // screens above it in the path, which is what auto_route does on the web
    // and not on the VM a test runs on.
    deepLinkBuilder: openedAt == null ? null : (_) => DeepLink.path(openedAt, includePrefixMatches: false),
  ),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => FTheme(
    data: buildAppTheme(),
    child: AppHeaderHost(child: child!),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    rootBundle.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async => utf8.decode(message!.buffer.asUint8List()) == Course.bundleAsset
          ? ByteData.sublistView(utf8.encode(jsonEncode(_course)))
          : null,
    );

    final python = createPythonRuntime();
    GetIt.I
      ..registerSingleton<AppRouter>(AppRouter())
      ..registerSingleton<BootstrapStatus>(BootstrapStatus())
      ..registerSingleton<PendingNavigationService>(PendingNavigationService())
      ..registerSingleton<LocaleController>(LocaleController())
      ..registerSingleton<ThemeModeController>(ThemeModeController())
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<CodeDraftStore>(CodeDraftStore())
      ..registerSingleton<TourStore>(TourStore())
      ..registerSingleton<MobileBrowserWarning>(MobileBrowserWarning(applies: false))
      ..registerSingleton<StartupProgress>(StartupProgress())
      ..registerSingleton<PythonRuntime>(python)
      ..registerSingleton<PythonAttemptRunner>(PythonAttemptRunner(python));
  });

  tearDown(GetIt.I.reset);

  Future<void> start(WidgetTester tester, {String? openedAt}) async {
    tester.view
      ..physicalSize = const Size(1000, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shell(openedAt: openedAt));
    await tester.pumpAndSettle();
  }

  testWidgets('an address pasted over an open catalog moves the catalog that is there', (tester) async {
    await start(tester);
    await _visit(tester, '/learn-python');
    final catalog = tester.state(find.byType(CatalogScreen));
    expect(_scroll(tester).pixels, 0);

    await _visit(tester, '/learn-python?group=week-2');

    // The page was handed new arguments rather than replaced, which is why the
    // catalog reads its anchor off its own widget at every build.
    expect(tester.state(find.byType(CatalogScreen)), same(catalog));
    expect(tester.getTopLeft(find.text('WEEK 2')).dy, closeTo(_arrived, 0.5));
    expect(GetIt.I<AppRouter>().currentUrl, '/learn-python?group=week-2', reason: 'the anchor stays in the address');
  });

  testWidgets('a cold start on an address with an anchor arrives at it, past the bootstrap', (tester) async {
    // The guard parks the address while the course loads, query and all.
    await start(tester, openedAt: '/learn-python?lesson=b3');

    expect(find.byType(CatalogScreen), findsOneWidget);
    expect(_scroll(tester).pixels, greaterThan(0));
    expect(tester.getTopLeft(find.text('WEEK 2')).dy, closeTo(_arrived, 0.5), reason: 'its heading stuck on the way');
  });

  testWidgets('a lesson\'s group crumb opens the catalog at that group, the second time as well', (tester) async {
    final semantics = tester.ensureSemantics();
    await start(tester);
    // Or the bar's introduction would be standing over the lesson.
    await GetIt.I<TourStore>().markSeen('lesson');

    Future<void> followTheCrumb() async {
      await tester.ensureVisible(find.text('b2', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('b2'));
      await tester.pumpAndSettle();
      expect(find.byType(LessonScreen), findsOneWidget);

      // A lesson opens with its bar put away.
      await tester.tap(find.bySemanticsLabel('Balk tonen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week 2'));
      await tester.pumpAndSettle();
    }

    await _visit(tester, '/learn-python');
    await followTheCrumb();

    expect(find.byType(CatalogScreen), findsOneWidget);
    expect(tester.getTopLeft(find.text('WEEK 2')).dy, closeTo(_arrived, 0.5));

    // Scrolled away and asked for the same group again. The address is the one
    // the catalog was already opened on, and the page still has to move.
    _scroll(tester).jumpTo(_scroll(tester).maxScrollExtent);
    await tester.pumpAndSettle();
    await followTheCrumb();

    expect(tester.getTopLeft(find.text('WEEK 2')).dy, closeTo(_arrived, 0.5));
    semantics.dispose();
  });
}
