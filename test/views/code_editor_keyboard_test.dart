import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/run_button.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

// Every test here runs as a desktop, and none of this file may build an editor
// under the default Android. re_editor reads the platform into a top-level
// final (`kIsAndroid`) on first use, so the first editor an isolate builds
// decides for all the others, and only the desktop editor binds Tab.
final TargetPlatformVariant _desktop = TargetPlatformVariant.desktop();

const String _leaveHint = 'Esc, dan Tab: verlaten';

/// What the app shell gives every screen: the theme, Dutch, a window, an
/// [Overlay], the Tab and Shift+Tab traversal `WidgetsApp` binds, which the
/// editor's own shortcuts sit under, and a focused scope, as a pushed route has.
/// Without one the first Tab reaches no shortcut at all.
Widget _app(Widget child, {Size size = const Size(1400, 1000)}) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: Shortcuts(
          shortcuts: WidgetsApp.defaultShortcuts,
          child: Actions(
            actions: WidgetsApp.defaultActions,
            child: FocusScope(
              autofocus: true,
              child: Overlay(initialEntries: [OverlayEntry(builder: (_) => child)]),
            ),
          ),
        ),
      ),
    ),
  ),
);

/// Whether the keyboard is on something inside [finder]'s widget.
bool _focusIn(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;

  final targets = finder.evaluate().toSet();
  var inside = targets.contains(focused);
  focused.visitAncestorElements((ancestor) {
    inside = targets.contains(ancestor);
    return !inside;
  });
  return inside;
}

bool _inEditor() => _focusIn(find.byType(CodeEditor));

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

/// The next control, the way a keyboard user gets there: Escape first while
/// the editor has the keyboard, since a Tab there indents.
Future<void> _moveOn(WidgetTester tester, {bool backwards = false}) async {
  if (_inEditor()) await _press(tester, LogicalKeyboardKey.escape);
  await _press(tester, LogicalKeyboardKey.tab, shift: backwards);
}

/// Moves on [steps] times from wherever the keyboard is, and names where it
/// lands each time by the first of [controls] it is inside.
Future<List<String>> _walk(WidgetTester tester, Map<String, Finder> controls, {int steps = 8}) async {
  final visited = <String>[];
  for (var step = 0; step < steps; step++) {
    await _moveOn(tester);
    visited.add([for (final MapEntry(:key, :value) in controls.entries) if (_focusIn(value)) key].firstOrNull ?? '?');
  }
  return visited;
}

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

/// A test run as each desktop. re_editor starts its caret from 100 ms timers
/// that nothing cancels, which the body is given time for at its end.
void _testKeys(String description, Future<void> Function(WidgetTester tester) body) {
  testWidgets(description, variant: _desktop, (tester) async {
    await body(tester);
    await tester.pump(const Duration(milliseconds: 150));
  });
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  group('CodeEditorCard', () {
    late FocusNode before;
    late FocusNode after;
    late CodeLineEditingController code;

    setUp(() {
      before = FocusNode(debugLabel: 'before');
      after = FocusNode(debugLabel: 'after');
      code = CodeLineEditingController.fromText('print(1)');
    });

    tearDown(() {
      before.dispose();
      after.dispose();
      code.dispose();
    });

    /// The card between two focusable neighbours, and the keyboard in it.
    Future<void> focusCard(WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: Column(
              children: [
                Focus(focusNode: before, child: const SizedBox(width: 400, height: 40)),
                CodeEditorCard(controller: code, status: 'Python', autofocus: false),
                Focus(focusNode: after, child: const SizedBox(width: 400, height: 40)),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(CodeEditor));
      await tester.pump();
      expect(_inEditor(), isTrue);
    }

    _testKeys('Tab alone indents, and the editor keeps the keyboard', (tester) async {
      await focusCard(tester);

      await _press(tester, LogicalKeyboardKey.tab);
      await _press(tester, LogicalKeyboardKey.tab);

      expect(_inEditor(), isTrue);
      expect(code.text.replaceAll(' ', ''), 'print(1)');
      expect(code.text.length, greaterThan('print(1)'.length), reason: 'both Tabs went into the code');
    });

    _testKeys('Escape then Tab moves on to the next control, and leaves the code alone', (tester) async {
      await focusCard(tester);

      await _press(tester, LogicalKeyboardKey.escape);
      await _press(tester, LogicalKeyboardKey.tab);

      expect(after.hasFocus, isTrue);
      expect(code.text, 'print(1)');
    });

    _testKeys('Escape then Shift+Tab moves back to the control before', (tester) async {
      await focusCard(tester);

      await _press(tester, LogicalKeyboardKey.escape);
      await _press(tester, LogicalKeyboardKey.tab, shift: true);

      expect(before.hasFocus, isTrue);
      expect(code.text, 'print(1)');
    });

    _testKeys('a key between Escape and Tab gives Tab back to the code', (tester) async {
      await focusCard(tester);

      await _press(tester, LogicalKeyboardKey.escape);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await _press(tester, LogicalKeyboardKey.tab);

      expect(_inEditor(), isTrue);
      expect(code.text.length, greaterThan('print(1)'.length));
    });

    _testKeys('the way out is stated only while the editor has the keyboard', (tester) async {
      await tester.pumpWidget(_app(CodeEditorCard(controller: code, status: 'Python', autofocus: false)));
      await tester.pump();
      expect(find.text(_leaveHint), findsNothing);

      await tester.tap(find.byType(CodeEditor));
      await tester.pump();
      expect(find.text(_leaveHint), findsOneWidget);
      expect(find.text('main.py'), findsOneWidget, reason: 'beside the file name, not in place of it');
      expect(find.text('Python'), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text(_leaveHint), findsNothing);
    });
  });

  group('a lesson', () {
    setUp(() {
      GetIt.I
        ..registerSingleton<Course>(
          Course(
            lessons: [
              CourseLesson(
                entry: Course.entriesFrom(['assets/lessons/python/01-loops.nl.md']).single,
                translations: {
                  'nl': const Lesson(
                    id: 'loops',
                    title: 'Loops',
                    sections: [
                      LessonSection(id: 'first', title: 'Eerste', kind: SectionKind.exercise, prose: '', starter: ''),
                      LessonSection(id: 'last', title: 'Laatste', kind: SectionKind.exercise, prose: '', starter: ''),
                    ],
                  ),
                },
              ),
            ],
          ),
        )
        ..registerSingleton<ProgressStore>(ProgressStore())
        ..registerSingleton<PythonRuntime>(_IdleRuntime())
        ..registerSingleton<PythonAttemptRunner>(PythonAttemptRunner(GetIt.I<PythonRuntime>()));
    });

    tearDown(GetIt.I.reset);

    _testKeys('opens with the keyboard in the editor, and every control is reached from it', (tester) async {
      await tester.pumpWidget(
        _app(
          const LessonScreen(languageSlug: 'learn-python', lessonId: 'loops', sectionId: 'first'),
          size: const Size(900, 2000),
        ),
      );
      await tester.pumpAndSettle();

      expect(_inEditor(), isTrue, reason: 'writing the code is what the step is for');
      expect(find.text(_leaveHint), findsOneWidget);

      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!;
      await _press(tester, LogicalKeyboardKey.tab);
      expect(_inEditor(), isTrue);
      expect(editor.text, isNot(''), reason: 'a Tab alone indents');

      final visited = await _walk(tester, {
        'editor': find.byType(CodeEditor),
        'back': find.byWidgetPredicate((widget) => widget is AppButton && widget.semanticsLabel == 'Terug naar Python'),
        'run': find.byType(RunButton),
      }, steps: 3);
      expect(visited, ['back', 'run', 'editor'], reason: 'out of the editor, round the page and back in');

      await _moveOn(tester, backwards: true);
      expect(_inEditor(), isFalse, reason: 'backwards out of it too');
    });
  });

}
