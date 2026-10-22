import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/lesson/code_sample.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Keeps the program it was asked to run, and answers with a passing verdict.
class _RecordingRuntime implements PythonRuntime {

  final List<String> programs = [];

  @override
  bool get isSupported => true;

  @override
  String? get version => 'Python 3.14.0';

  @override
  Future<void> ready() async {}

  @override
  Future<PythonResult> run(String code, {String stdin = ''}) async {
    programs.add(code);
    return PythonResult(
      stdout: '\n${PythonAttemptRunner.sentinel}${jsonEncode({'ok': true, 'output': '', 'tests': <Object>[]})}\n',
      stderr: '',
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

}

final CourseLesson _lesson = CourseLesson(
  entry: const LessonEntry(subject: 'python', order: 1, paths: {'nl': 'x'}),
  translations: {
    'nl': Lesson(
      id: 'testen',
      title: 'Testen',
      sections: [
        LessonSection(
          id: 'eerste',
          title: 'Eerste',
          kind: SectionKind.exercise,
          prose: '',
          starter: 'from rekenmachine import deel\n',
          run: SectionRun.pytest,
          fileName: 'test_rekenmachine.py',
          files: {'rekenmachine.py': 'def deel(a, b):\n    return a / b\n', 'cijfers.csv': 'naam,cijfer\n'},
        ),
      ],
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
  late _RecordingRuntime runtime;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    runtime = _RecordingRuntime();
    GetIt.I
      ..registerSingleton<Course>(Course(lessons: [_lesson]))
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<CodeDraftStore>(CodeDraftStore())
      ..registerSingleton<PythonRuntime>(runtime)
      ..registerSingleton<PythonAttemptRunner>(PythonAttemptRunner(runtime));
  });

  tearDown(GetIt.I.reset);

  testWidgets('a pytest step shows its module above the editor, and runs pytest', (tester) async {
    await tester.pumpWidget(_app(const LessonScreen(subjectSlug: 'learn-python', lessonId: 'testen', sectionId: 'eerste')));
    await tester.pumpAndSettle();

    final given = find.byWidgetPredicate((widget) => widget is CodeSample && widget.label == 'rekenmachine.py');
    expect(given, findsOneWidget);
    expect(tester.getTopLeft(given).dy, lessThan(tester.getTopLeft(find.byType(CodeEditorCard)).dy));
    expect(find.text('test_rekenmachine.py'), findsOneWidget, reason: "the editor's strip names its file");
    // A data file stays a button in the files card, the way any step shows it.
    expect(find.byWidgetPredicate((widget) => widget is CodeSample && widget.label == 'cijfers.csv'), findsNothing);
    expect(find.text('cijfers.csv'), findsOneWidget);

    await tester.ensureVisible(find.text('Controleer code'));
    await tester.tap(find.text('Controleer code'));
    await tester.pumpAndSettle();

    expect(runtime.programs.single, contains('make_run_tests'));
    // Lets re_editor's caret timer finish before the test ends.
    await tester.pump(const Duration(milliseconds: 150));
  });
}
