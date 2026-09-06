import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
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

  /// Which pairs of a match-pairs board have been put together, per step, as
  /// indices into that section's own `pairs`.
  ///
  /// Per step for the reason [_code] is: stepping back and forward again finds
  /// the board as it was left. It is **not** seeded from [ProgressStore], which
  /// remembers that a step passed and not how — so a finished lesson opens on an
  /// empty board that may be played again, with the way on already offered.
  @readonly
  Map<int, Set<int>> _matchedPairs = {};

  /// The tiles standing picked on the current step, at most two.
  @readonly
  Set<PairHalf> _picked = {};

  /// What the student has typed into a predict-output step's box, per step.
  ///
  /// Per step for the reason [_matchedPairs] is: stepping away and back finds
  /// the answer as it was left. Kept here rather than only in the field's own
  /// controller because the button that runs the program is disabled until
  /// there is something to compare, and that is a decision the view has to make
  /// during its own build.
  @readonly
  Map<int, String> _predictions = {};

  /// The prediction the run in flight was started with — or, once it lands, the
  /// one the verdict on screen is about.
  ///
  /// Held apart from [_predictions] on purpose: the box stays where it is after
  /// the answer appears, and a student who types into it MUST NOT silently turn
  /// a wrong prediction into a right one.
  @readonly
  String? _prediction;

  /// A run is in flight, which turns Run into Stop — the one thing that can be
  /// asked of a program that is already going.
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

  /// Which way the student last moved, which is the direction the step that is
  /// leaving slides out and the one arriving slides in.
  ///
  /// Not derived from the step numbers by the view: it MUST be read at the
  /// moment of the move, and by the time the view rebuilds the step it is
  /// leaving is already gone.
  @readonly
  bool _forward = true;

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

  /// The pairs already matched on the step being shown.
  Set<int> get matched => _matchedPairs[_step] ?? const {};

  /// What has been typed into the step being shown, on a predict-output step.
  String get typedPrediction => _predictions[_step] ?? '';

  /// Two tiles are picked, which can only mean they do not belong together: a
  /// pair that matched cleared them both. They stay showing until the next tap,
  /// which starts the pick over rather than adding a third tile to it.
  bool get pickedWrong => _picked.length == 2;

  /// Picks one tile of a match-pairs board.
  ///
  /// A pick that completes a pair records it and clears the board; one that does
  /// not leaves both tiles standing, which is the only feedback a wrong guess
  /// gets — and the next tap starts the pick over rather than adding a third
  /// tile to it. Tapping a tile that is already picked puts it back.
  @action
  void pick(PairHalf tile) {
    final standing = pickedWrong ? const <PairHalf>{} : _picked;

    if (standing.contains(tile)) {
      _picked = {...standing}..remove(tile);
      return;
    }

    _picked = {...standing, tile};
    if (_picked.length < 2) return;

    // Two tiles of one pair are always its two halves: a tile is picked at most
    // once, so the second cannot be the first over again.
    final (first, second) = (_picked.first, _picked.last);
    if (first.pair != second.pair) return;

    _matchedPairs = {..._matchedPairs, _step: {...matched, first.pair}};
    _picked = {};
  }

  @action
  void goTo(int step) {
    // Off the end page is always backwards: it sits past the last step, so
    // every step in the lesson is behind it.
    _forward = !_completed && step > _step;
    _step = step;
    _attempt = null;
    _running = false;
    // What is already matched is kept, but a half-made pick is not: it belongs
    // to the moment it was made.
    _picked = {};
    // The typed prediction is kept for the same reason the matched pairs are;
    // the one the verdict was about goes with the verdict.
    _prediction = null;
    // Leaves the end page: the progress bar and the trail can both reach past
    // it back into the lesson.
    _completed = false;
  }

  /// Shows the lesson's end page, after the last step.
  @action
  void complete() {
    _forward = true;
    _completed = true;
  }

  /// Notes that the tick just recorded is what finished the lesson.
  @action
  void noteLessonFinished() => _earnedCelebration = true;

  @action
  void setCode(String code) => _code = {..._code, _step: code};

  @action
  void setPrediction(String prediction) => _predictions = {..._predictions, _step: prediction};

  /// [prediction] is what a predict-output step was answered with, and null on
  /// every other kind — there is nothing to compare a written program against.
  @action
  void startRun({String? prediction}) {
    _running = true;
    _attempt = null;
    _prediction = prediction;
  }

  /// Marks the current step done without a run behind it, for an info step,
  /// which has nothing to check.
  @action
  void markPassed() => _passed = {..._passed, _step};

  /// Ends a run that was stopped — by the student, or by their leaving the step
  /// it belongs to.
  ///
  /// Clears the verdict rather than writing one: there is nothing to say about a
  /// program that was not allowed to finish, and what it had printed died with
  /// the worker that was holding it.
  @action
  void stopRun() {
    _running = false;
    _attempt = null;
    _prediction = null;
  }

  @action
  void finishRun(AttemptResult result) {
    _running = false;
    _attempt = result;
    if (result.passed) _passed = {..._passed, _step};
  }

}
