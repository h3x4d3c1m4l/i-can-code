import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/course_icon.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/lesson/confetti_burst.dart';
import 'package:i_can_code/views/components/lesson/lesson_complete_panel.dart';
import 'package:i_can_code/views/components/lesson/requirements_row.dart';
import 'package:i_can_code/views/components/microbit/microbit_docs_button.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/components/output_card.dart';
import 'package:i_can_code/views/components/run_button.dart';
import 'package:i_can_code/views/components/vm/run_notice.dart';
import 'package:i_can_code/views/components/vm/vm_load_panel.dart';
import 'package:i_can_code/views/components/vm/vm_run_dialog.dart';
import 'package:i_can_code/views/project_screen/components/project_block.dart';
import 'package:i_can_code/views/project_screen/project_screen_controller.dart';
import 'package:i_can_code/views/project_screen/project_screen_view.dart';
import 'package:i_can_code/views/project_screen/project_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fake_vm_runtime.dart';

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

const String _windowStarter = 'import tkinter as tk\n\nroot = tk.Tk()\nroot.mainloop()\n';

/// A project on the machine: a window, then a button in it.
const List<LessonSection> _windowSections = [
  LessonSection(id: 'about', title: 'Wat je maakt', kind: SectionKind.info, prose: 'Een venster met een knop.'),
  LessonSection(
    id: 'label',
    title: 'Een label',
    kind: SectionKind.task,
    prose: 'Zet een label in het venster.',
    doneWhen: 'Je ziet een label.',
    starter: _windowStarter,
  ),
  LessonSection(id: 'button', title: 'Een knop', kind: SectionKind.task, prose: 'Voeg een knop toe.', doneWhen: 'De knop werkt.'),
];

const VmWindow _window = VmWindow(xid: 11, title: 'Mijn venster', mapped: true, isRoot: true, width: 240, height: 120);

const String _showWindowFirst = 'Laat je programma eerst een venster tonen, dan kun je dit aanklikken.';

CourseLesson get _project => GetIt.I<Course>().lessons.last;

CourseLesson get _windowProject =>
    GetIt.I<Course>().lessons.firstWhere((lesson) => lesson.translations.values.first.id == 'window');

/// Lets events from the machine reach the screen. Two frames: an Observer
/// invalidated in the middle of a frame waits for its end before it rebuilds
/// (flutter_mobx's `_markNeedsBuildImmediatelyOrDelayed`).
Future<void> _deliver(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    GetIt.I
      ..registerSingleton<Course>(
        Course(
          lessons: [
            CourseLesson(
              entry: const LessonEntry(subject: 'python', order: 1, paths: {'nl': 'x'}),
              translations: {
                'nl': const Lesson(
                  id: 'loops',
                  title: 'Herhalen',
                  sections: [LessonSection(id: 'a', title: 'A', kind: SectionKind.info, prose: '')],
                ),
              },
            ),
            CourseLesson(
              entry: const LessonEntry(subject: 'python', order: 2, paths: {'nl': 'w'}),
              translations: {
                'nl': const Lesson(
                  id: 'window',
                  title: 'Een venster',
                  icon: CourseIcon.window,
                  layout: LessonLayout.project,
                  runtime: LessonRuntime.tkinter,
                  sections: _windowSections,
                ),
              },
            ),
            CourseLesson(
              entry: const LessonEntry(subject: 'python', order: 3, paths: {'nl': 'y'}),
              translations: {
                'nl': const Lesson(
                  id: 'dice',
                  title: 'Dobbelsteen',
                  icon: CourseIcon.dice,
                  layout: LessonLayout.project,
                  runtime: LessonRuntime.microbit,
                  sections: _sections,
                ),
              },
            ),
          ],
        ),
      )
      ..registerSingleton<FeatureToggles>(FeatureToggles())
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<CodeDraftStore>(CodeDraftStore())
      ..registerSingleton<EditorSettings>(EditorSettings());
  });

  tearDown(() async {
    await GetIt.I<CodeDraftStore>().flush();
    await GetIt.I.reset();
  });

  /// The project [lessonId]. A [createRuntime] of the test's own stands in for
  /// the machine of a build that ships its image; without one the project is
  /// built the way `flutter test` builds it, with no image.
  (ProjectScreenController, ProjectScreenViewModel, BuildContextAccessor) open({
    String lessonId = 'dice',
    VmRuntime Function()? createRuntime,
  }) {
    final accessor = BuildContextAccessor();
    final viewModel = ProjectScreenViewModel(contextAccessor: accessor, subjectSlug: 'learn-python', lessonId: lessonId);
    final controller = ProjectScreenController(
      viewModel: viewModel,
      contextAccessor: accessor,
      createRuntime: createRuntime,
      imageIncluded: createRuntime != null,
    );

    return (controller, viewModel, accessor);
  }

  group('the section in front of the student', () {
    test('is the first one not finished, and it is the one open', () {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      expect(viewModel.current, 0);
      expect(viewModel.open, 0);
      expect(viewModel.code.text, _starter, reason: 'the editor opens on the first task\'s starter');
    });

    test('its editor indents by the four spaces Python asks for', () {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      expect(viewModel.code.options.indentSize, 4);
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
      viewModel.code.text = 'display.show(4)';
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

      viewModel.noteTried();
      expect(viewModel.triedHere, isTrue);

      await controller.finish(1);
      expect(viewModel.triedHere, isFalse, reason: 'the next task has not been tried on the board yet');
    });

    test('waits again after a Verdieping is skipped too', () async {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      await controller.finish(0);
      await controller.finish(1);
      viewModel.noteTried();
      controller.skip(2);

      expect(viewModel.triedHere, isFalse, reason: 'the task after the skipped one has not been tried yet');
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

      expect(viewModel.code.text, 'print(1)');
    });

    test('is forgotten when it is the starter again', () {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      viewModel.code.text = 'print(1)';
      expect(GetIt.I<CodeDraftStore>().workFor(_project), 'print(1)');

      viewModel.code.text = _starter;
      expect(GetIt.I<CodeDraftStore>().workFor(_project), isNull);
    });

    test('can be replaced by a finished task\'s snapshot', () async {
      final (controller, viewModel, _) = open();
      addTearDown(controller.dispose);

      viewModel.code.text = 'versie 1';
      await controller.finish(0);
      await controller.finish(1);
      viewModel.code.text = 'kapot';

      controller.restore(controller.snapshotOf(_sections[1])!);
      expect(viewModel.code.text, 'versie 1');
    });
  });

  group('a project on the machine', () {
    late List<FakeVmRuntime> runtimes;

    setUp(() => runtimes = []);

    VmRuntime createRuntime() {
      final created = FakeVmRuntime();
      runtimes.add(created);
      return created;
    }

    test('has a machine and no board, and starts loading it at once', () {
      final (controller, viewModel, _) = open(lessonId: 'window', createRuntime: createRuntime);
      addTearDown(controller.dispose);

      expect(viewModel.board, isNull);
      expect(controller.board, isNull);
      expect(viewModel.machine, isNotNull);
      expect(runtimes.single.loads, 1);
    });

    test('opens on the first task\'s starter, indented as Python asks, and keeps what is typed', () {
      final (controller, viewModel, _) = open(lessonId: 'window', createRuntime: createRuntime);
      addTearDown(controller.dispose);

      expect(viewModel.code.text, _windowStarter);
      expect(viewModel.code.options.indentSize, 4);

      viewModel.code.text = 'import tkinter\n';
      expect(GetIt.I<CodeDraftStore>().workFor(_windowProject), 'import tkinter\n');
    });

    test('comes back with the program of the last visit, and forgets it at the starter again', () {
      GetIt.I<CodeDraftStore>().keepWork(_windowProject, 'print(1)');
      final (controller, viewModel, _) = open(lessonId: 'window', createRuntime: createRuntime);
      addTearDown(controller.dispose);

      expect(viewModel.code.text, 'print(1)');

      viewModel.code.text = _windowStarter;
      expect(GetIt.I<CodeDraftStore>().workFor(_windowProject), isNull);
    });

    testWidgets('Run keeps the program at once', (tester) async {
      final (controller, viewModel, _) = open(lessonId: 'window', createRuntime: createRuntime);
      addTearDown(controller.dispose);
      runtimes.single.ready();
      await tester.pump();

      viewModel.code.text = 'print(3)';
      controller.run();
      await tester.pump();

      final reloaded = CodeDraftStore();
      await reloaded.load(GetIt.I<Course>());
      expect(reloaded.workFor(_windowProject), 'print(3)', reason: 'a tab discarded while the program runs reloads with it');
    });

    test('runs what is in the editor, and leaving frees the machine', () async {
      final (controller, viewModel, _) = open(lessonId: 'window', createRuntime: createRuntime);
      runtimes.single.ready();
      await Future<void>.delayed(Duration.zero);

      controller.run();
      expect(runtimes.single.lastSource, _windowStarter);
      expect(viewModel.machine!.running, isTrue);

      controller.dispose();
      expect(runtimes.single.disposed, isTrue);
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
    Future<(ProjectScreenController, ProjectScreenViewModel)> pump(
      WidgetTester tester,
      Size size, {
      String lessonId = 'dice',
      VmRuntime Function()? createRuntime,
    }) async {
      final (controller, viewModel, accessor) = open(lessonId: lessonId, createRuntime: createRuntime);
      final view = ProjectScreenView(
        viewModel: viewModel,
        controller: controller,
        contextAccessor: accessor,
        displayViewBuilder: fakeVmView,
      );
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

    testWidgets('the documentation is offered before any board is connected', (tester) async {
      const size = Size(1400, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(tester, size);

      expect(find.byType(MicrobitDocsButton), findsOneWidget);
    });

    testWidgets('writing without a board asks for one, and writes once there is one', (tester) async {
      const size = Size(1400, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final (_, viewModel) = await pump(tester, size);
      expect(find.text('Sluit je micro:bit aan'), findsNothing, reason: 'no panel about it on the page');

      await tester.tap(find.text('Draai code'));
      await tester.pumpAndSettle();
      // The test's link is the stub, which no browser can use.
      expect(find.text('Dit werkt niet in deze browser'), findsOneWidget);

      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
      expect(find.text('Dit werkt niet in deze browser'), findsNothing);
      expect(viewModel.board!.status, isNot(MicrobitStatus.flashing));

      await tester.tap(find.text('Draai code'));
      await tester.pumpAndSettle();
      viewModel.board!.setStatus(MicrobitStatus.connected);
      // Not `pumpAndSettle`: the write that follows never ends against the
      // stub, and its button keeps spinning.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Dit werkt niet in deze browser'), findsNothing, reason: 'a board closes the dialog');
      expect(viewModel.board!.status, MicrobitStatus.flashing, reason: 'and the program goes to it');
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

      viewModel.noteTried();
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

      viewModel.noteTried();
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

    group('a project on the machine', () {
      late List<FakeVmRuntime> runtimes;

      setUp(() => runtimes = []);

      FakeVmRuntime runtime() => runtimes.last;

      VmRuntime createRuntime() {
        final created = FakeVmRuntime();
        runtimes.add(created);
        return created;
      }

      void useWindow(WidgetTester tester, Size size) {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }

      AppButton works(WidgetTester tester) => tester.widget<AppButton>(find.widgetWithText(AppButton, 'Het werkt!'));

      for (final (name, size) in [('side by side', const Size(1400, 900)), ('stacked', const Size(800, 1400))]) {
        testWidgets('lays out $name, with Run and the machine where the board was', (tester) async {
          useWindow(tester, size);
          await pump(tester, size, lessonId: 'window', createRuntime: createRuntime);

          expect(tester.takeException(), isNull);
          expect(find.byType(ProjectBlock), findsNWidgets(_windowSections.length));
          expect(find.byType(RunButton), findsOneWidget);
          expect(find.byType(VmLoadPanel), findsOneWidget, reason: 'the machine loads as the project opens');
          expect(find.text('Draai code'), findsNothing);
          expect(find.byType(MicrobitDocsButton), findsNothing, reason: 'the documentation is the board\'s');

          runtime().ready();
          await _deliver(tester);

          expect(find.byType(VmLoadPanel), findsNothing);
          expect(find.text('Python 3.12.12 · Tk 8.6.16'), findsOneWidget, reason: 'the machine names itself');
        });
      }

      testWidgets('"Het werkt!" waits for the run in flight to show a window, and asks again for the next task', (
        tester,
      ) async {
        const size = Size(1400, 900);
        useWindow(tester, size);
        final (_, viewModel) = await pump(tester, size, lessonId: 'window', createRuntime: createRuntime);
        runtime().ready();
        await _deliver(tester);

        await tester.tap(find.text('Gelezen'));
        await tester.pumpAndSettle();
        expect(works(tester).onPress, isNull);
        expect(find.text(_showWindowFirst), findsOneWidget);

        await tester.tap(find.text('Uitvoeren'));
        await tester.pumpAndSettle();
        expect(find.byType(VmRunDialog), findsOneWidget, reason: 'the program runs over the whole page');
        final id = runtime().lastRunId;

        runtime().emit(VmWindows(id, const [VmWindow(xid: 11, title: 'Mijn venster', mapped: false, isRoot: true)]));
        await _deliver(tester);
        expect(works(tester).onPress, isNull, reason: 'a window that is not mapped shows nothing');

        runtime().emit(VmWindows(id, const [_window]));
        await _deliver(tester);
        expect(viewModel.triedHere, isTrue);

        // The student closes the window, which ends the program and the dialog.
        runtime().end(id, const VmExit(reason: VmEndReason.closed, signal: 9));
        await _deliver(tester);
        expect(find.byType(VmRunDialog), findsNothing);
        expect(works(tester).onPress, isNotNull);
        expect(find.text(_showWindowFirst), findsNothing);

        await tester.tap(find.text('Het werkt!'));
        await tester.pumpAndSettle();

        expect(GetIt.I<ProgressStore>().finishedIn(_windowProject), {'about', 'label'});
        expect(viewModel.current, 2);
        expect(viewModel.triedHere, isFalse);
        expect(works(tester).onPress, isNull, reason: 'the next task has not run yet');
        expect(find.text(_showWindowFirst), findsOneWidget);
      });

      testWidgets('a run that ends without ever showing a window leaves "Het werkt!" waiting', (tester) async {
        const size = Size(1400, 900);
        useWindow(tester, size);
        final (_, viewModel) = await pump(tester, size, lessonId: 'window', createRuntime: createRuntime);
        runtime().ready();
        await _deliver(tester);
        await tester.tap(find.text('Gelezen'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Uitvoeren'));
        await tester.pumpAndSettle();
        final id = runtime().lastRunId;
        // A program that crashed before Tk mapped its window.
        runtime()
          ..emit(VmWindows(id, const [VmWindow(xid: 11, title: 'Mijn venster', mapped: false, isRoot: true)]))
          ..end(id, const VmExit(reason: VmEndReason.exit, code: 1));
        await _deliver(tester);

        expect(find.byType(VmRunDialog), findsNothing);
        expect(viewModel.triedHere, isFalse);
        expect(works(tester).onPress, isNull, reason: 'a program that ended before its window showed showed nothing');
        expect(find.text(_showWindowFirst), findsOneWidget);
      });

      testWidgets('while a program runs, the page behind it takes no press, no focus and no screen reader', (
        tester,
      ) async {
        const size = Size(1400, 900);
        useWindow(tester, size);
        final semantics = tester.ensureSemantics();
        final (_, viewModel) = await pump(tester, size, lessonId: 'window', createRuntime: createRuntime);
        runtime().ready();
        await _deliver(tester);
        expect(find.semantics.byLabel('Gelezen').evaluate(), isNotEmpty);

        await tester.tap(find.text('Uitvoeren'));
        await tester.pumpAndSettle();

        expect(tester.getRect(find.byType(VmRunDialog)), Offset.zero & size, reason: 'the tasks are under it too');
        await tester.tap(find.text('Gelezen'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(viewModel.current, 0, reason: 'the dim takes a press meant for the tasks');
        expect(find.semantics.byLabel('Gelezen').evaluate(), isEmpty);

        for (var step = 0; step < 6; step++) {
          FocusManager.instance.primaryFocus!.nextFocus();
          await tester.pump();
          final focused = find.byElementPredicate((element) => element == FocusManager.instance.primaryFocus!.context);
          expect(find.ancestor(of: focused, matching: find.byType(ProjectBlock)), findsNothing, reason: 'step $step');
          expect(find.ancestor(of: focused, matching: find.byType(CodeEditorCard)), findsNothing, reason: 'step $step');
        }
        semantics.dispose();
      });

      testWidgets('Run hands the keyboard to the program, over a page that moves nothing while it runs', (tester) async {
        const size = Size(1400, 900);
        useWindow(tester, size);
        await pump(tester, size, lessonId: 'window', createRuntime: createRuntime);
        runtime().ready();
        await _deliver(tester);

        await tester.tap(find.text('Uitvoeren'));
        await tester.pumpAndSettle();
        runtime().emit(VmWindows(runtime().lastRunId, const [_window]));
        await _deliver(tester);

        expect(runtime().display.keyboardEnabled, isTrue);
        expect(find.text('Esc, dan Tab: verlaten'), findsOneWidget);
        // The emulator shares the page's thread, so nothing may ask for frames.
        for (var second = 0; second < 3; second++) {
          await tester.pump(const Duration(seconds: 1));
          expect(tester.hasRunningAnimations, isFalse);
          expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
        }

        await tester.tap(find.byIcon(FLucideIcons.x));
        await tester.pumpAndSettle();
        expect(runtime().stops, 1, reason: 'the cross ends the program');
        expect(find.byType(VmRunDialog), findsNothing);
      });

      testWidgets('Run right after "Het werkt!" asks for no frames while the program runs', (tester) async {
        const size = Size(1400, 900);
        useWindow(tester, size);
        await pump(tester, size, lessonId: 'window', createRuntime: createRuntime);
        runtime().ready();
        await _deliver(tester);
        await tester.tap(find.text('Gelezen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Uitvoeren'));
        await tester.pumpAndSettle();
        runtime()
          ..emit(VmWindows(runtime().lastRunId, const [_window]))
          ..end(runtime().lastRunId, const VmExit(reason: VmEndReason.closed, signal: 9));
        await _deliver(tester);

        // The task's confetti, its block folding away and the next one opening
        // are all still under way when the next run starts.
        await tester.tap(find.text('Het werkt!'));
        await tester.pump(const Duration(milliseconds: 100));
        final burst = tester.state(find.byType(ConfettiBurst));
        await tester.tap(find.text('Uitvoeren'));
        await tester.pump();
        runtime().emit(VmWindows(runtime().lastRunId, const [_window]));
        await _deliver(tester);

        for (var second = 0; second < 3; second++) {
          await tester.pump(const Duration(seconds: 1));
          expect(tester.hasRunningAnimations, isFalse);
          expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
        }

        runtime().end(runtime().lastRunId, const VmExit(reason: VmEndReason.closed, signal: 9));
        await _deliver(tester);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(ConfettiBurst)), same(burst), reason: 'the burst carried on, and did not fire again');
      });

      for (final (name, size) in [('side by side', const Size(1400, 900)), ('stacked', const Size(800, 1400))]) {
        testWidgets('$name, the notice and the output of the last run are under Run', (tester) async {
          useWindow(tester, size);
          await pump(tester, size, lessonId: 'window', createRuntime: createRuntime);
          runtime().ready();
          await _deliver(tester);

          await tester.ensureVisible(find.text('Uitvoeren'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Uitvoeren'));
          await tester.pumpAndSettle();
          final id = runtime().lastRunId;
          runtime()
            ..emit(VmOutput(id, 'Hallo\n', fromStderr: false))
            ..emit(VmRunHint(id, VmHint.tkNoMainloop))
            ..end(id, const VmExit(reason: VmEndReason.exit, code: 0));
          await _deliver(tester);

          expect(find.byType(RunNotice), findsOneWidget);
          expect(find.textContaining('mainloop()'), findsOneWidget);
          expect(tester.widget<OutputCard>(find.byType(OutputCard)).text, 'Hallo');
        });
      }

      testWidgets('a machine that failed says so under Run, and Retry builds a new one', (tester) async {
        const size = Size(1400, 900);
        useWindow(tester, size);
        await pump(tester, size, lessonId: 'window', createRuntime: createRuntime);
        runtime().emit(const VmFailed(VmFailure.network, 'HTTP 404'));
        await _deliver(tester);

        expect(find.text('De machine kon niet worden gedownload'), findsOneWidget);
        await tester.ensureVisible(find.text('Opnieuw proberen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Opnieuw proberen'));
        await tester.pumpAndSettle();

        expect(runtimes, hasLength(2));
        expect(runtimes.first.disposed, isTrue);
        expect(runtimes.last.loads, 1);
        expect(find.byType(VmLoadPanel), findsOneWidget);
      });

      testWidgets('a browser that cannot host the machine says so, and downloads nothing', (tester) async {
        const size = Size(1400, 900);
        useWindow(tester, size);
        await pump(
          tester,
          size,
          lessonId: 'window',
          createRuntime: () {
            final created = FakeVmRuntime(supported: false);
            runtimes.add(created);
            return created;
          },
        );

        expect(find.text('Dit werkt niet in deze browser'), findsOneWidget);
        expect(find.textContaining('De lessen zelf werken gewoon'), findsNothing, reason: 'this lesson does not');
        expect(runtime().loads, 0);
        expect(tester.widget<RunButton>(find.byType(RunButton)).onRun, isNull);
      });

      testWidgets('a build without the machine\'s image says so, as the Tkinter page does', (tester) async {
        const size = Size(1400, 900);
        useWindow(tester, size);
        await pump(tester, size, lessonId: 'window');

        expect(find.text('Tkinter zit niet in deze versie van de app'), findsOneWidget);
        expect(find.textContaining('De lessen zelf werken gewoon'), findsNothing, reason: 'this lesson does not');
        expect(tester.widget<RunButton>(find.byType(RunButton)).onRun, isNull);
      });
    });
  });
}
