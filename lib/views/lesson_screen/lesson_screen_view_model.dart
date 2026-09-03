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

  /// The lesson's end page is showing — the step past the last one.
  ///
  /// Deliberately **not** a [LessonSection]: the lesson format knows nothing
  /// about it, so it counts towards no `stepCount`, no progress and no dot on
  /// the progress bar. It is not in the address either, so a reload comes back
  /// to the last step rather than here.
  @readonly
  bool _completed = false;

  /// This visit is what finished the lesson — the one moment worth confetti.
  ///
  /// Set when the tick that completes the lesson lands, and held for as long as
  /// the screen lives, so the end page still celebrates a lesson that was
  /// finished by filling a gap in the middle. Opening a lesson already finished
  /// never sets it: a tick that was already there is not an achievement.
  @readonly
  bool _earnedCelebration = false;

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

  /// Whether this language has another lesson after this one, which is what
  /// puts "Volgende les" on the end page.
  bool get hasNextLesson => GetIt.I<Course>().lessonAfter(lesson) != null;

  @action
  void goTo(int step) {
    _step = step;
    _attempt = null;
    _running = false;
    // Leaves the end page: the progress bar and the trail can both reach past
    // it back into the lesson.
    _completed = false;
  }

  /// Shows the lesson's end page, after the last step.
  @action
  void complete() => _completed = true;

  /// Notes that the tick just recorded is what finished the lesson.
  @action
  void noteLessonFinished() => _earnedCelebration = true;

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
