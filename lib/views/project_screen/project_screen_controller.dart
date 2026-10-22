import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/routing/catalog_anchor.dart';
import 'package:i_can_code/services/feature_toggles.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/vm/vm_image.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/components/lesson/requirements_row.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_controller.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/components/vm/vm_session_controller.dart';
import 'package:i_can_code/views/components/vm/vm_session_view_model.dart';
import 'package:i_can_code/views/project_screen/project_screen_view_model.dart';

class ProjectScreenController extends ScreenControllerBase<ProjectScreenViewModel> {

  final ProgressStore _progress = GetIt.I<ProgressStore>();
  final CodeDraftStore _drafts = GetIt.I<CodeDraftStore>();

  /// The board half of a micro:bit project: permission, flashing and the
  /// output. Null where [ProjectScreenViewModel.board] is.
  late final MicrobitSessionController? board;

  /// The machine half of a project on `runtime: tkinter`: the download, the
  /// runs and what they report. Null where [ProjectScreenViewModel.machine] is.
  late final VmSessionController? machine;

  bool _disposed = false;

  /// Writes the program out when the app is hidden. On the web that is also a
  /// tab being closed or reloaded, which takes the store's pending write with it.
  late final AppLifecycleListener _lifecycle;

  /// [createRuntime] and [imageIncluded] are for tests of a project on the
  /// machine; it makes its own otherwise, and takes the last from the build
  /// ([vmImageIncluded]).
  ProjectScreenController({
    required super.viewModel,
    required super.contextAccessor,
    VmRuntime Function()? createRuntime,
    bool imageIncluded = vmImageIncluded,
  }) {
    board = switch (viewModel.board) {
      final MicrobitSessionViewModel session => MicrobitSessionController(
        viewModel: session,
        contextAccessor: contextAccessor,
        // The program is meant to run, so nothing interrupts the board on its
        // way into it.
        interrupt: false,
        onFlashed: viewModel.noteTried,
      ),
      null => null,
    };
    machine = switch (viewModel.machine) {
      final VmSessionViewModel session => VmSessionController(
        viewModel: session,
        contextAccessor: contextAccessor,
        onWindowShown: viewModel.noteTried,
        createRuntime: createRuntime,
        imageIncluded: imageIncluded,
      ),
      null => null,
    };
    viewModel.code.addListener(_keepWork);
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(_drafts.flush()));
  }

  /// Runs the program on the machine, and writes it out at once: ChromeOS
  /// discards a tab this heavy first, and it reloads with only what was written.
  void run() {
    final machine = this.machine;
    if (_disposed || machine == null || !machine.viewModel.canRun) return;
    unawaited(_drafts.flush());
    machine.run();
  }

  /// Keeps the shared program for the next visit, or forgets it when it is the
  /// starter again, so a starter the author rewrites still reaches a student
  /// who never touched it.
  void _keepWork() {
    final code = viewModel.code.text;
    if (viewModel.starters.contains(code)) {
      _drafts.forgetWork(viewModel.lesson);
    } else {
      _drafts.keepWork(viewModel.lesson, code);
    }
  }

  /// The student says the section at [index] is done: read, or working.
  ///
  /// A task also keeps the program as it stands, as that task's snapshot.
  Future<void> finish(int index) async {
    final section = viewModel.lesson.translations.values.first.sections[index];
    final wasFinished = _progress.isFinished(viewModel.lesson);

    if (section.kind == SectionKind.task) {
      _drafts.keepSnapshot(viewModel.lesson, section.id, viewModel.code.text);
      unawaited(_drafts.flush());
    }
    viewModel.finish(index);

    await _progress.markFinished(viewModel.lesson, section.id);
    if (_disposed) return;
    if (!wasFinished && _progress.isFinished(viewModel.lesson)) viewModel.noteProjectFinished();
  }

  /// Passes over an optional section without recording it.
  void skip(int index) => viewModel.skip(index);

  /// The program as it stood when task [section] was said to work.
  String? snapshotOf(LessonSection section) => _drafts.snapshotFor(viewModel.lesson, section.id);

  /// Puts [code] back in the editor, in place of whatever is there.
  void restore(String code) => viewModel.code.text = code;

  /// The lessons [section] recommends, in [locale]. See [requirementsFor].
  List<Requirement> requirementsOf(LessonSection section, String locale) => requirementsFor(
    section.requires,
    subject: viewModel.lesson.entry.subject,
    locale: locale,
    course: GetIt.I<Course>(),
    progress: _progress,
  );

  /// Opens a lesson a task recommends, over this screen, so Back returns here.
  ///
  /// A project on the machine opened from here takes this screen's machine, if
  /// it has one, and [VmSessionController] hands it back when that one closes.
  Future<void> openRequirement(CourseLesson lesson) async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    unawaited(_drafts.flush());
    await contextAccessor.buildContext.router.push(openingRoute(lesson, _progress));
  }

  void moreConfetti() => viewModel.addExtraBurst();

  /// Opens the lesson after this one, the way [LessonScreenController] does.
  Future<void> openNextLesson() async {
    final next = visibleLessonAfter(viewModel.lesson);
    if (next == null) return openSubject();
    if (_disposed || !contextAccessor.buildContext.mounted) return;

    await contextAccessor.buildContext.router.replaceAll([
      const SubjectsRoute(),
      CatalogRoute(subjectSlug: subjectSlug(next.entry.subject)),
      openingRoute(next, _progress),
    ]);
  }

  /// Opens this project's catalog at [group]: scrolled to its heading, which
  /// lights up.
  Future<void> openGroup(LessonGroup group) async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([
      const SubjectsRoute(),
      catalogRoute(
        subjectSlug: subjectSlug(viewModel.lesson.entry.subject),
        anchor: (kind: CatalogAnchorKind.group, id: group.id),
      ),
    ]);
  }

  /// Opens this project's catalog.
  Future<void> openSubject() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([
      const SubjectsRoute(),
      CatalogRoute(subjectSlug: subjectSlug(viewModel.lesson.entry.subject)),
    ]);
  }

  /// Returns to the app's home.
  Future<void> leave() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const SubjectsRoute()]);
  }

  @override
  void dispose() {
    _disposed = true;
    viewModel.code.removeListener(_keepWork);
    unawaited(_drafts.flush());
    _lifecycle.dispose();
    board?.dispose();
    machine?.dispose();
    super.dispose();
  }

}
