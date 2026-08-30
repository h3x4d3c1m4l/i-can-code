import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'progress_store.g.dart';

class ProgressStore = ProgressStoreBase with _$ProgressStore;

/// Which steps a student has finished, remembered between visits.
///
/// Keyed on [LessonSection.id] rather than a step's position, so a tick survives
/// a section being inserted, reordered or retitled.
///
/// **Per browser**, not per person, and a convenience rather than a record:
/// every read and write swallows its own failure, and nothing may depend on this
/// being right.
abstract class ProgressStoreBase with Store {

  /// One key per lesson. The language is part of it because a lesson id is only
  /// unique within its own language directory.
  static String keyFor(String language, String lessonId) => 'progress.$language.$lessonId';

  final SharedPreferencesAsync _preferences;

  /// Finished section ids, by [keyFor]. Observable so a tick appears on the
  /// catalog the moment a step is passed.
  @readonly
  Map<String, Set<String>> _finished = {};

  ProgressStoreBase({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  /// Reads what was saved. Called once, by the initialization screen.
  ///
  /// A failure is swallowed: a browser that refuses storage MUST NOT keep the
  /// app from starting.
  Future<void> load(Course course) async {
    final loaded = <String, Set<String>>{};

    for (final lesson in course.lessons) {
      final key = keyFor(lesson.entry.language, lesson.translations.values.first.id);
      try {
        final stored = await _preferences.getStringList(key);
        if (stored != null && stored.isNotEmpty) loaded[key] = stored.toSet();
      } on Object {
        // Treated as "nothing saved for this lesson".
      }
    }

    _replace(loaded);
  }

  /// The finished sections of [lesson].
  Set<String> finishedIn(CourseLesson lesson) =>
      _finished[keyFor(lesson.entry.language, lesson.translations.values.first.id)] ?? const {};

  /// How many of [lesson]'s steps are done. Counts only sections the lesson
  /// still has, so a section removed by an author stops counting on its own.
  int completedSteps(CourseLesson lesson) {
    final done = finishedIn(lesson);
    return lesson.translations.values.first.sections.where((section) => done.contains(section.id)).length;
  }

  bool isFinished(CourseLesson lesson) => completedSteps(lesson) == lesson.translations.values.first.stepCount;

  bool isStarted(CourseLesson lesson) => completedSteps(lesson) > 0;

  /// Whether anything at all has been recorded, which is what decides if
  /// offering to clear it is worth showing.
  @computed
  bool get hasProgress => _finished.values.any((sections) => sections.isNotEmpty);

  /// The step to open [lesson] at — the first one not yet finished, as an index.
  /// A finished lesson returns 0 and so restarts from the beginning.
  int firstUnfinishedStep(CourseLesson lesson) {
    final done = finishedIn(lesson);
    final sections = lesson.translations.values.first.sections;
    final next = sections.indexWhere((section) => !done.contains(section.id));
    return next == -1 ? 0 : next;
  }

  /// Records [sectionId] as done and writes it out.
  Future<void> markFinished(CourseLesson lesson, String sectionId) async {
    final key = keyFor(lesson.entry.language, lesson.translations.values.first.id);
    if (_finished[key]?.contains(sectionId) ?? false) return;

    final updated = {...?_finished[key], sectionId};
    _replace({..._finished, key: updated});

    try {
      await _preferences.setStringList(key, updated.toList());
    } on Object {
      // The tick stands for this session either way.
    }
  }

  /// Forgets everything, in storage as well as in memory.
  Future<void> clear() async {
    for (final key in _finished.keys) {
      try {
        await _preferences.remove(key);
      } on Object {
        // Nothing to do about a storage that will not forget.
      }
    }
    _replace({});
  }

  @action
  void _replace(Map<String, Set<String>> value) => _finished = value;

}
