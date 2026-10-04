import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/components/lesson/lesson_complete_panel.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/project_screen/components/project_block.dart';
import 'package:i_can_code/views/project_screen/project_screen_controller.dart';
import 'package:i_can_code/views/project_screen/project_screen_view.dart';
import 'package:i_can_code/views/project_screen/project_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

const String _starter = 'from microbit import *\n';

const List<LessonSection> _sections = [
  LessonSection(id: 'intro', title: 'Wat je bouwt', kind: SectionKind.info, prose: 'Een dobbelsteen.'),
  LessonSection(
    id: 'roll',
    title: 'Eén worp',
    kind: SectionKind.task,
    prose: 'Gooi een getal.',
    doneWhen: 'Er verschijnt een getal.',
    requires: ['loops', 'not-a-lesson'],
    starter: _starter,
  ),
  LessonSection(
    id: 'faces',
    title: 'Ogen',
    kind: SectionKind.task,
    prose: 'Teken ogen.',
    doneWhen: 'Je ziet ogen.',
    optional: true,
  ),
  LessonSection(id: 'shake', title: 'Schudden', kind: SectionKind.task, prose: 'Schud.', doneWhen: 'Het werkt.'),
];

CourseLesson get _project => GetIt.I<Course>().lessons.firstWhere((l) => l.entry.slug == 'dice');

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    final entries = Course.entriesFrom([
      'assets/lessons/python/01-loops.nl.md',
      'assets/lessons/python/microbit/01-dice.nl.md',
    ]);
    GetIt.I
      ..registerSingleton<Course>(
        Course(
          lessons: [
            CourseLesson(
              entry: entries.first,
              translations: {
                'nl': const Lesson(
                  id: 'loops',
                  title: 'Herhalen',
                  sections: [LessonSection(id: 'a', title: 'A', kind: SectionKind.info, prose: '')],
                ),
              },
            ),
            CourseLesson(
              entry: entries.last,
              translations: {
                'nl': const Lesson(
                  id: 'dice',
                  title: 'Dobbelsteen',
                  emoji: '🎲',
                  layout: LessonLayout.project,
                  runtime: LessonRuntime.microbit,
                  sections: _sections,
                ),
              },
            ),
          ],
        ),
      )
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<CodeDraftStore>(CodeDraftStore());
  });

  tearDown(() async {
    await GetIt.I<CodeDraftStore>().flush();
    await GetIt.I.reset();
  });

  (ProjectScreenController, ProjectScreenViewModel, BuildContextAccessor) open() {
    final accessor = BuildContextAccessor();
    final viewModel = ProjectScreenViewModel(contextAccessor: accessor, subjectSlug: 'learn-python', lessonId: 'dice');

    return (ProjectScreenController(viewModel: viewModel, contextAccessor: accessor), viewModel, accessor);
  }

  group('the section in front of the student', () {
    test('is the first one not finished, and it is the one open', () {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      expect(viewModel.current, 0);
      expect(viewModel.open, 0);
      expect(viewModel.board.code.text, _starter, reason: 'the editor opens on the first task\'s starter');
    });

    test('moves on once read, and the next one opens', () async {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      await controller.finish(0);

      expect(viewModel.current, 1);
      expect(viewModel.open, 1);
      expect(GetIt.I<ProgressStore>().finishedIn(_project), {'intro'});
      expect(viewModel.passBursts, 0, reason: 'reading is not worth confetti');
    });

    test('keeps a snapshot of a task said to work', () async {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      await controller.finish(0);
      viewModel.board.code.text = 'display.show(4)';
      await controller.finish(1);

      expect(viewModel.current, 2);
      expect(GetIt.I<ProgressStore>().finishedIn(_project), {'intro', 'roll'});
      expect(controller.snapshotOf(_sections[1]), 'display.show(4)');
      expect(viewModel.passBursts, 1);
    });

    test('is one open at a time, and one still ahead does not open', () async {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      await controller.finish(0);
      viewModel.toggle(0);
      expect(viewModel.open, 0, reason: 'opening a finished one closes the current one');

      viewModel.toggle(3);
      expect(viewModel.open, 0, reason: 'a section ahead does not open');

      viewModel.toggle(0);
      expect(viewModel.open, isNull, reason: 'pressing the open one closes it');
    });

    test('waits for the program to have been on the board again', () async {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      viewModel.noteFlashed();
      expect(viewModel.flashedHere, isTrue);

      await controller.finish(1);
      expect(viewModel.flashedHere, isFalse, reason: 'the next task has not been tried on the board yet');
    });

    test('passes over a Verdieping without recording it', () async {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      await controller.finish(0);
      await controller.finish(1);
      controller.skip(2);

      expect(viewModel.current, 3);
      expect(viewModel.open, 3);
      expect(GetIt.I<ProgressStore>().finishedIn(_project), isNot(contains('faces')));
    });

    test('is not a Verdieping skipped on an earlier visit, once a later section was finished', () async {
      await GetIt.I<ProgressStore>().markFinished(_project, 'roll');
      await GetIt.I<ProgressStore>().markFinished(_project, 'shake');

      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      expect(viewModel.current, isNull, reason: 'the project is done; "faces" stays behind as skipped');
      expect(viewModel.open, isNull);
    });
  });

  group('the shared program', () {
    test('comes back on the next visit', () {
      GetIt.I<CodeDraftStore>().keepWork(_project, 'print(1)');

      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      expect(viewModel.board.code.text, 'print(1)');
    });

    test('is forgotten when it is the starter again', () {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      viewModel.board.code.text = 'print(1)';
      expect(GetIt.I<CodeDraftStore>().workFor(_project), 'print(1)');

      viewModel.board.code.text = _starter;
      expect(GetIt.I<CodeDraftStore>().workFor(_project), isNull);
    });

    test('can be replaced by a finished task\'s snapshot', () async {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      viewModel.board.code.text = 'versie 1';
      await controller.finish(0);
      await controller.finish(1);
      viewModel.board.code.text = 'kapot';

      controller.restore(controller.snapshotOf(_sections[1])!);
      expect(viewModel.board.code.text, 'versie 1');
    });
  });

  test('recommends the lessons the course has, and says how far the student is', () async {
    final (controller, _, _) = open();
    addTearDown(controller.dispose);

    final loops = GetIt.I<Course>().lessons.first;
    expect(controller.requirementsOf(_sections[1], 'nl').single.status, RequirementStatus.notStarted);

    await GetIt.I<ProgressStore>().markFinished(loops, 'a');
    final requirements = controller.requirementsOf(_sections[1], 'nl');

    expect(requirements.map((r) => r.title), ['Herhalen'], reason: 'an id the course lacks is left out');
    expect(requirements.single.status, RequirementStatus.finished);
  });

  group('on screen', () {
    Future<(ProjectScreenController, ProjectScreenViewModel)> pump(WidgetTester tester, Size size) async {
      final (controller, viewModel, accessor) = open();
      final view = ProjectScreenView(viewModel: viewModel, controller: controller, contextAccessor: accessor);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        FTheme(
          data: buildAppTheme(),
          child: Localizations(
            locale: const Locale('nl'),
            delegates: AppLocalizations.localizationsDelegates,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: MediaQueryData(size: size),
                // A Navigator, which brings its own Overlay: the dialogs push
                // routes, the way they do under the app's router.
                child: Navigator(
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (context, _, _) {
                      accessor.buildContext = context;
                      return view.body;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (controller, viewModel);
    }

    for (final (name, size) in [('side by side', const Size(1400, 900)), ('stacked', const Size(800, 1400))]) {
      testWidgets('lays out $name', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pump(tester, size);

        expect(tester.takeException(), isNull);
        expect(find.byType(ProjectBlock), findsNWidgets(_sections.length), reason: 'every section is a block');
        expect(find.text('Een dobbelsteen.'), findsOneWidget, reason: 'the first one is open');
        expect(find.text('Gelezen'), findsOneWidget);
        expect(find.textContaining('Schudden'), findsOneWidget, reason: 'a section ahead shows its title');
        expect(find.text('Schud.'), findsNothing, reason: 'and not what it says');
      });
    }

    testWidgets('writing without a board asks for one, and writes once there is one', (tester) async {
      const size = Size(1400, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (_, viewModel) = await pump(tester, size);
      expect(find.text('Sluit je micro:bit aan'), findsNothing, reason: 'no panel about it on the page');

      await tester.tap(find.text('Naar het bordje schrijven'));
      await tester.pumpAndSettle();
      // The test's link is the stub, which no browser can use.
      expect(find.text('Dit werkt niet in deze browser'), findsOneWidget);

      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
      expect(find.text('Dit werkt niet in deze browser'), findsNothing);
      expect(viewModel.board.status, isNot(MicrobitStatus.flashing));

      await tester.tap(find.text('Naar het bordje schrijven'));
      await tester.pumpAndSettle();
      viewModel.board.setStatus(MicrobitStatus.connected);
      // Not `pumpAndSettle`: the write that follows never ends against the
      // stub, and its button keeps spinning.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Dit werkt niet in deze browser'), findsNothing, reason: 'a board closes the dialog');
      expect(viewModel.board.status, MicrobitStatus.flashing, reason: 'and the program goes to it');
    });

    testWidgets('the end of the project scrolls all the way into view', (tester) async {
      // Short enough that the end panel starts below the window.
      const size = Size(1400, 700);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final id in ['intro', 'roll', 'faces']) {
        await GetIt.I<ProgressStore>().markFinished(_project, id);
      }
      final (_, viewModel) = await pump(tester, size);

      viewModel.noteFlashed();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Het werkt!'));
      await tester.pumpAndSettle();

      final panel = tester.getRect(find.byType(LessonCompletePanel));
      expect(panel.bottom, lessThanOrEqualTo(size.height), reason: 'the whole panel is in view');
      expect(panel.top, greaterThanOrEqualTo(0));
    });

        testWidgets('each block leads to the next: "Gelezen", then "Het werkt!"', (tester) async {
      const size = Size(1400, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (_, viewModel) = await pump(tester, size);

      await tester.tap(find.text('Gelezen'));
      await tester.pumpAndSettle();
      expect(find.text('Een dobbelsteen.'), findsNothing, reason: 'the block read folds away');
      expect(find.text('Gooi een getal.'), findsOneWidget, reason: 'and the next one opens');

      await tester.tap(find.text('Het werkt!'));
      await tester.pumpAndSettle();
      expect(viewModel.current, 1, reason: 'nothing was put on the board yet');

      viewModel.noteFlashed();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Het werkt!'));
      await tester.pumpAndSettle();

      expect(viewModel.current, 2);
      expect(find.text('Code bekijken'), findsOneWidget);
      expect(find.text('Teken ogen.'), findsOneWidget);

      await tester.tap(find.textContaining('Wat je bouwt'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Teken ogen.'), findsOneWidget, reason: 'halfway, the block closing is still folding away');

      await tester.pumpAndSettle();
      expect(find.text('Een dobbelsteen.'), findsOneWidget, reason: 'a finished block opens again');
      expect(find.text('Teken ogen.'), findsNothing, reason: 'and the one being worked on closes');
    });
  });
}
