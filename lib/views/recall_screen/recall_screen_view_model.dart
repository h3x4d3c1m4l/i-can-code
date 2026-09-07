import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/progress/recall_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/views/base/screen_view_model_base.dart';
import 'package:mobx/mobx.dart';

part 'recall_screen_view_model.g.dart';

class RecallScreenViewModel = RecallScreenViewModelBase with _$RecallScreenViewModel;

/// One run through a refresher: a handful of steps from lessons that are done
/// and due, asked again with the scaffolding taken away.
abstract class RecallScreenViewModelBase extends ScreenViewModelBase with Store {

  final String language;

  /// What this session asks, fixed when it opens.
  ///
  /// Built once rather than recomputed: a session that re-picked its items
  /// while the student was working through it would change under them as the
  /// ladder moved.
  late final List<RecallItem> items = _pick();

  /// Which item is showing.
  @readonly
  int _index = 0;

  /// The last attempt for the item showing, or null before the first Run.
  @readonly
  AttemptResult? _attempt;

  @readonly
  bool _running = false;

  /// The items answered correctly, as indices into [items].
  @readonly
  Set<int> _passed = {};

  /// What has been typed into a predict item's box, per item.
  @readonly
  Map<int, String> _predictions = {};

  /// The prediction the run in flight was started with, and once it lands the
  /// one the verdict on screen is about. Held apart from [_predictions] so that
  /// typing into the box afterwards cannot rewrite a verdict already given.
  @readonly
  String? _prediction;

  /// The session is over and its end page is showing.
  @readonly
  bool _completed = false;

  RecallScreenViewModelBase({required super.contextAccessor, required String languageSlug})
    : language = languageFromSlug(languageSlug) ?? '';

  bool get hasItems => items.isNotEmpty;

  RecallItem get item => items[_index];

  /// What has been typed into the item showing.
  String get typedPrediction => _predictions[_index] ?? '';

  /// Whether every lesson this session drew from was answered without a miss.
  /// Read per lesson by the controller when it settles the ladder.
  bool passedEveryItemOf(CourseLesson lesson) => items.indexed
      .where((entry) => identical(entry.$2.lesson, lesson))
      .every((entry) => _passed.contains(entry.$1));

  /// The lessons this session drew from, each once.
  List<CourseLesson> get lessons {
    final seen = <CourseLesson>[];
    for (final item in items) {
      if (!seen.any((lesson) => identical(lesson, item.lesson))) seen.add(item.lesson);
    }
    return seen;
  }

  @action
  void setPrediction(String prediction) => _predictions = {..._predictions, _index: prediction};

  @action
  void startRun({String? prediction}) {
    _running = true;
    _attempt = null;
    _prediction = prediction;
  }

  @action
  void stopRun() {
    _running = false;
    _attempt = null;
    _prediction = null;
  }

  /// [passed] is decided by the controller rather than read off [result],
  /// because the two item kinds mean different things by it: a written answer
  /// passes when its validator says so, a prediction when it matched.
  @action
  void finishRun(AttemptResult result, {required bool passed}) {
    _running = false;
    _attempt = result;
    if (passed) _passed = {..._passed, _index};
  }

  /// On to the next item, or to the end page after the last.
  @action
  void advance() {
    if (_index + 1 < items.length) {
      _index++;
      _attempt = null;
      _running = false;
      _prediction = null;
      return;
    }
    _completed = true;
    _running = false;
  }

  /// The steps worth asking about again: from lessons that are **finished** —
  /// `ProgressStore`'s to say — and **due** — `RecallStore`'s.
  ///
  /// Nothing is filtered on how long ago: a lesson with no schedule at all is
  /// due, which is how a browser that lost its storage still gets offered a
  /// refresher rather than silently never getting one again.
  List<RecallItem> _pick() {
    final progress = GetIt.I<ProgressStore>();
    final recall = GetIt.I<RecallStore>();

    return recallSession([
      for (final lesson in GetIt.I<Course>().lessonsFor(language))
        if (progress.isFinished(lesson) && recall.isDue(lesson)) lesson,
    ]);
  }

}
