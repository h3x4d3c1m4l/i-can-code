import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_controller.dart';
import 'package:i_can_code/views/project_screen/project_screen_view_model.dart';

/// How far a student is with a lesson a task recommends.
enum RequirementStatus { finished, started, notStarted }

/// One lesson a task recommends, ready to be drawn.
typedef Requirement = ({String title, RequirementStatus status, CourseLesson lesson});

class ProjectScreenController extends ScreenControllerBase<ProjectScreenViewModel> {

  final ProgressStore _progress = GetIt.I<ProgressStore>();
  final CodeDraftStore _drafts = GetIt.I<CodeDraftStore>();

  /// The board half of the screen: permission, flashing and the output.
  late final MicrobitSessionController board;

  bool _disposed = false;

  /// Writes the program out when the app is hidden. On the web that is also a
  /// tab being closed or reloaded, which takes the store's pending write with it.
  late final AppLifecycleListener _lifecycle;

  ProjectScreenController({required super.viewModel, required super.contextAccessor}) {
    board = MicrobitSessionController(
      viewModel: viewModel.board,
      contextAccessor: contextAccessor,
      // The program is meant to run, so nothing interrupts the board on its
      // way into it.
      interrupt: false,
      onFlashed: viewModel.noteFlashed,
    );
    viewModel.board.code.addListener(_keepWork);
    _lifecycle = AppLifecycleListener(onHide: () => unawaited(_drafts.flush()));
  }

  /// Keeps the shared program for the next visit, or forgets it when it is the
  /// starter again, so a starter the author rewrites still reaches a student
  /// who never touched it.
  void _keepWork() {
    final code = viewModel.board.code.text;
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
      _drafts.keepSnapshot(viewModel.lesson, section.id, viewModel.board.code.text);
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
  void restore(String code) => viewModel.board.code.text = code;

  /// The lessons [section] recommends, in [locale], each with how far the
  /// student is. An id the course does not have is left out: the content test
  /// is what catches it, and a student can do nothing about it.
  List<Requirement> requirementsOf(LessonSection section, String locale) {
    final course = GetIt.I<Course>();
    final subject = viewModel.lesson.entry.subject;

    return [
      for (final id in section.requires)
        if (course.lessonsFor(subject).where((l) => l.translations.values.first.id == id).firstOrNull
            case final CourseLesson lesson)
          (
            title: lesson.forLocale(locale).title,
            status: _progress.isFinished(lesson)
                ? RequirementStatus.finished
                : _progress.isStarted(lesson)
                ? RequirementStatus.started
                : RequirementStatus.notStarted,
            lesson: lesson,
          ),
    ];
  }

  /// Opens a lesson a task recommends, over this screen, so Back returns here.
  Future<void> openRequirement(CourseLesson lesson) async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    unawaited(_drafts.flush());
    await contextAccessor.buildContext.router.push(openingRoute(lesson, _progress));
  }

  void moreConfetti() => viewModel.addExtraBurst();

  /// Opens the lesson after this one, the way [LessonScreenController] does.
  Future<void> openNextLesson() async {
    final next = GetIt.I<Course>().lessonAfter(viewModel.lesson);
    if (next == null) return openSubject();
    if (_disposed || !contextAccessor.buildContext.mounted) return;

    await contextAccessor.buildContext.router.replaceAll([
      const SubjectsRoute(),
      CatalogRoute(subjectSlug: subjectSlug(next.entry.subject)),
      openingRoute(next, _progress),
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
    viewModel.board.code.removeListener(_keepWork);
    unawaited(_drafts.flush());
    _lifecycle.dispose();
    board.dispose();
    super.dispose();
  }

}
