import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'lesson_screen_view_model.g.dart';

class LessonScreenViewModel = LessonScreenViewModelBase with _$LessonScreenViewModel;

abstract class LessonScreenViewModelBase extends ScreenViewModelBase with Store {

  /// The lesson being worked through, in every locale it has.
  final CourseLesson lesson;

  /// Which step the student is on, as an index.
  @readonly
  int _step;

  /// What the student has typed, per step. A step absent from this map has not
  /// been touched, so its editor still shows the starter block.
  @readonly
  Map<int, String> _code = {};

  /// The last attempt for the current step, or null before the first Run.
  @readonly
  AttemptResult? _attempt;

  /// A run is in flight, which disables Run so a second cannot start.
  @readonly
  bool _running = false;

  /// Steps the student has already passed, as indices into the current lesson.
  /// Seeded from [ProgressStore], which keys on section ids.
  @readonly
  Set<int> _passed = {};

  /// The address named a section this lesson does not have — `resume`, or a
  /// stale bookmark. The screen rewrites it to the step it landed on.
  final bool addressNeedsRewrite;

  LessonScreenViewModelBase({
    required super.contextAccessor,
    required String lessonId,
    required String? sectionId,
  }) : lesson = GetIt.I<Course>().lessons.firstWhere((l) => l.translations.values.first.id == lessonId),
       addressNeedsRewrite = !GetIt.I<Course>().lessons
           .firstWhere((l) => l.translations.values.first.id == lessonId)
           .translations
           .values
           .first
           .sections
           .any((section) => section.id == sectionId),
       _step = 0 {
    final sections = lesson.translations.values.first.sections;
    final named = sections.indexWhere((section) => section.id == sectionId);

    // An unknown id resolves the same way an absent one does.
    _step = named == -1 ? GetIt.I<ProgressStore>().firstUnfinishedStep(lesson) : named;

    final finished = GetIt.I<ProgressStore>().finishedIn(lesson);
    _passed = {
      for (final (index, section) in sections.indexed)
        if (finished.contains(section.id)) index,
    };
  }

  @action
  void goTo(int step) {
    _step = step;
    _attempt = null;
    _running = false;
  }

  @action
  void setCode(String code) => _code = {..._code, _step: code};

  @action
  void startRun() {
    _running = true;
    _attempt = null;
  }

  /// Marks the current step done without a run behind it, for an info step,
  /// which has nothing to check.
  @action
  void markPassed() => _passed = {..._passed, _step};

  @action
  void finishRun(AttemptResult result) {
    _running = false;
    _attempt = result;
    if (result.passed) _passed = {..._passed, _step};
  }

}
