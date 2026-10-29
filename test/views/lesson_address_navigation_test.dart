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
import 'package:i_can_code/services/color_vision_controller.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/services/feature_toggles.dart';
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
import 'package:i_can_code/views/components/app_header_host.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen.dart';
import 'package:i_can_code/views/project_screen/project_screen.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const String _root = 'assets/lessons/python';

/// A lesson of one reading step and a project of one task, one of each screen.
final Map<String, String> _course = {
  '$_root/contents.nl.md': '# Week 1 {#week-1}\n- [Hallo](hallo.md)\n- [Dobbel](dobbel.md)',
  '$_root/hallo.md':
      '# Hallo\n\n```metadata\nid: hallo\nicon: list\n```\n\n'
      '## Stap\n\n```metadata\ntype: info\nid: stap\nemoji: "🧪"\n```\n\nTekst.\n',
  '$_root/dobbel.md':
      '# Dobbel\n\n```metadata\nid: dobbel\nicon: dice\nlayout: project\nruntime: microbit\n```\n\n'
      '## Worp\n\n```metadata\ntype: task\nid: worp\nemoji: "🎲"\n```\n\nGooi.\n\n'
      '```done-when\nEr staat een getal.\n```\n\n```python-assignment\nfrom microbit import *\n```\n',
};

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
    // auto_route asks `dart:ui` for the first address, which a test cannot set.
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
      ..registerSingleton<ColorVisionController>(ColorVisionController())
      ..registerSingleton<FeatureToggles>(FeatureToggles())
      ..registerSingleton<EditorSettings>(EditorSettings())
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
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shell(openedAt: openedAt));
    await tester.pumpAndSettle();
  }

  testWidgets('a cold start on a project\'s address under the board lands on the subject picker', (tester) async {
    // Where projects lived before they had a segment of their own: it now reads
    // as the step "hallo" of a lesson called "microbit".
    await start(tester, openedAt: '/learn-python/$microbitLesson/hallo');

    expect(find.byType(SubjectsScreen), findsOneWidget);
    expect(GetIt.I<AppRouter>().currentPath, '/');
  });

  testWidgets('a lesson the course does not have lands on the subject picker', (tester) async {
    await start(tester);

    await _visit(tester, '/learn-python/bestaat-niet');

    expect(find.byType(SubjectsScreen), findsOneWidget);
    expect(GetIt.I<AppRouter>().currentPath, '/');
  });

  testWidgets('a project the course does not have lands on the subject picker', (tester) async {
    await start(tester);

    await _visit(tester, '/learn-python/$projectSegment/bestaat-niet');

    expect(find.byType(SubjectsScreen), findsOneWidget);
    expect(GetIt.I<AppRouter>().currentPath, '/');
  });

  testWidgets('a lesson the course has still opens', (tester) async {
    await start(tester);
    await GetIt.I<TourStore>().markSeen('lesson');

    await _visit(tester, '/learn-python/hallo/stap');

    expect(find.byType(LessonScreen), findsOneWidget);
  });

  testWidgets('a lesson under the project segment goes on to the lesson screen', (tester) async {
    await start(tester);
    await GetIt.I<TourStore>().markSeen('lesson');

    await _visit(tester, '/learn-python/$projectSegment/hallo');

    expect(find.byType(LessonScreen), findsOneWidget);
    expect(GetIt.I<AppRouter>().currentPath, '/learn-python/hallo/stap');
  });

  testWidgets('a project at a lesson\'s address goes on to the project screen', (tester) async {
    await start(tester);

    await _visit(tester, '/learn-python/dobbel/worp');

    expect(find.byType(ProjectScreen), findsOneWidget);
    expect(GetIt.I<AppRouter>().currentPath, '/learn-python/$projectSegment/dobbel');
  });
}
