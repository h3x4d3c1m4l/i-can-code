import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/lesson/requirements_row.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A runtime nothing in these tests runs anything on.
class _IdleRuntime implements PythonRuntime {

  @override
  bool get isSupported => true;

  @override
  String? get version => 'Python 3.15.0';

  @override
  Future<void> ready() async {}

  @override
  Future<PythonResult> run(String code, {String stdin = ''}) async => const PythonResult(stdout: '', stderr: '');

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

}

LessonSection _info(String id) => LessonSection(id: id, title: 'Stap $id', kind: SectionKind.info, prose: 'prose');

final CourseLesson _testen = CourseLesson(
  entry: const LessonEntry(subject: 'python', order: 1, paths: {'nl': 'a'}),
  translations: {'nl': Lesson(id: 'je-code-testen', title: 'Je code testen', sections: [_info('een')])},
);

final CourseLesson _mocking = CourseLesson(
  entry: const LessonEntry(subject: 'python', order: 2, paths: {'nl': 'b'}),
  translations: {
    'nl': Lesson(
      id: 'mocking',
      title: 'Mocking',
      requires: const ['je-code-testen', 'bestaat-niet'],
      sections: [_info('eerste'), _info('tweede')],
    ),
  },
);

Widget _app(Widget child) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(900, 2000)),
        child: FocusScope(
          autofocus: true,
          child: Overlay(initialEntries: [OverlayEntry(builder: (_) => child)]),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final runtime = _IdleRuntime();
    GetIt.I
      ..registerSingleton<Course>(Course(lessons: [_testen, _mocking]))
      ..registerSingleton<FeatureToggles>(FeatureToggles())
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<CodeDraftStore>(CodeDraftStore())
      ..registerSingleton<PythonRuntime>(runtime)
      ..registerSingleton<PythonAttemptRunner>(PythonAttemptRunner(runtime));
  });

  tearDown(GetIt.I.reset);

  Future<void> open(WidgetTester tester, String sectionId) async {
    await tester.pumpWidget(_app(LessonScreen(subjectSlug: 'learn-python', lessonId: 'mocking', sectionId: sectionId)));
    await tester.pumpAndSettle();
  }

  testWidgets('the first step names the lessons worth doing first, under its title', (tester) async {
    await open(tester, 'eerste');

    final row = tester.widget<RequirementsRow>(find.byType(RequirementsRow));
    expect(row.requirements.map((r) => (r.title, r.status)), [('Je code testen', RequirementStatus.notStarted)],
        reason: 'an id the course does not have is left out');
    expect(find.text('Handig om eerst te doen:'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(RequirementsRow)).dy, greaterThan(tester.getTopLeft(find.text('Stap eerste')).dy));
  });

  testWidgets('it marks a lesson the student already finished', (tester) async {
    await GetIt.I<ProgressStore>().markFinished(_testen, 'een');
    await open(tester, 'eerste');

    expect(tester.widget<RequirementsRow>(find.byType(RequirementsRow)).requirements.single.status, RequirementStatus.finished);
  });

  testWidgets('a later step does not repeat it', (tester) async {
    await open(tester, 'tweede');

    expect(find.byType(RequirementsRow), findsNothing);
  });
}
