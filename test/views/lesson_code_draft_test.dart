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
import 'package:i_can_code/views/components/run_button.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A runtime nothing in these tests runs anything on.
class _IdleRuntime implements PythonRuntime {

  @override
  bool get isSupported => true;

  @override
  String? get version => 'Python 3.14.0';

  @override
  Future<void> ready() async {}

  @override
  Future<PythonResult> run(String code, {String stdin = ''}) async => const PythonResult(stdout: '', stderr: '');

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

}

/// One exercise whose starter differs per locale, which is what a comment in the
/// starter block does.
final CourseLesson _lesson = CourseLesson(
  entry: LessonEntry(language: 'python', order: 1, slug: 'loops', paths: const {'nl': 'x', 'en': 'y'}),
  translations: {
    for (final (locale, starter) in [('nl', '# Schrijf hier'), ('en', '# Write here')])
      locale: Lesson(
        id: 'loops',
        title: 'Loops',
        sections: [
          LessonSection(id: 'first', title: 'Eerste', kind: SectionKind.exercise, prose: '', starter: starter),
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

Future<CodeLineEditingController> _openLesson(WidgetTester tester) async {
  await tester.pumpWidget(_app(const LessonScreen(languageSlug: 'learn-python', lessonId: 'loops', sectionId: 'first')));
  await tester.pumpAndSettle();
  return tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
}

/// What a fresh store over the same storage reads back, which is what a reload
/// produces.
Future<String?> _stored() async {
  final reloaded = CodeDraftStore();
  await reloaded.load(Course(lessons: [_lesson]));
  return reloaded.codeFor(_lesson, 'first');
}

/// Types into the editor the way the keyboard does: by changing its text, which
/// the lesson screen hears as a change like any other.
Future<void> _type(WidgetTester tester, CodeLineEditingController editor, String code) async {
  editor.text = code;
  await tester.pump();
}

/// A test that settles re_editor's caret blink before it ends, which leaves a
/// timer pending after every edit.
void _testDrafts(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pump(const Duration(milliseconds: 150));
  });
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    GetIt.I
      ..registerSingleton<Course>(Course(lessons: [_lesson]))
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<CodeDraftStore>(CodeDraftStore())
      ..registerSingleton<PythonRuntime>(_IdleRuntime())
      ..registerSingleton<PythonAttemptRunner>(PythonAttemptRunner(GetIt.I<PythonRuntime>()));
  });

  tearDown(GetIt.I.reset);

  _testDrafts('an untouched exercise opens on its starter', (tester) async {
    final editor = await _openLesson(tester);

    expect(editor.text, '# Schrijf hier');
  });

  _testDrafts('an exercise opens on what was typed into it before', (tester) async {
    GetIt.I<CodeDraftStore>().keep(_lesson, 'first', 'print("terug")');

    final editor = await _openLesson(tester);

    expect(editor.text, 'print("terug")');
  });

  _testDrafts('a pause in typing writes it out, and not every keystroke', (tester) async {
    final editor = await _openLesson(tester);

    await _type(tester, editor, 'print(1)');
    expect(await _stored(), isNull);

    await tester.pump(CodeDraftStoreBase.writeDelay);
    expect(await _stored(), 'print(1)');
  });

  _testDrafts('a run writes it out at once', (tester) async {
    final editor = await _openLesson(tester);
    await _type(tester, editor, 'print(1)');

    await tester.tap(find.byType(RunButton));
    await tester.pump();

    expect(await _stored(), 'print(1)');
  });

  _testDrafts('leaving the lesson writes it out at once', (tester) async {
    final editor = await _openLesson(tester);
    await _type(tester, editor, 'print(1)');
    // re_editor's caret timer outlives its editor, so it runs out first. Still
    // well inside the write delay.
    await tester.pump(const Duration(milliseconds: 150));

    await tester.pumpWidget(const SizedBox());

    expect(await _stored(), 'print(1)');
  });

  _testDrafts('hiding the app writes it out at once', (tester) async {
    final editor = await _openLesson(tester);
    await _type(tester, editor, 'print(1)');

    // On the web a closed or reloaded tab is hidden first, and takes the
    // pending write with it.
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final stored = await _stored();
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(stored, 'print(1)');
  });

  _testDrafts('back to the starter forgets the draft, the way a reset does', (tester) async {
    final editor = await _openLesson(tester);
    final drafts = GetIt.I<CodeDraftStore>();

    await _type(tester, editor, 'print(1)');
    expect(drafts.hasDrafts, isTrue);

    await _type(tester, editor, '# Schrijf hier');
    expect(drafts.hasDrafts, isFalse);
  });

  _testDrafts("another language's starter is not a draft either", (tester) async {
    // An editor keeps its text across a change of language, so a reset after
    // one lands on the new language's starter.
    final editor = await _openLesson(tester);

    final drafts = GetIt.I<CodeDraftStore>();

    await _type(tester, editor, 'print(1)');
    expect(drafts.hasDrafts, isTrue);

    await _type(tester, editor, '# Write here');
    expect(drafts.hasDrafts, isFalse);
  });
}
