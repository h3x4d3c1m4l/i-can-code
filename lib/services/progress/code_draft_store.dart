import 'dart:async';

import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'code_draft_store.g.dart';

class CodeDraftStore = CodeDraftStoreBase with _$CodeDraftStore;

/// What a student last typed into each exercise, so a reload or a later visit
/// finds their code where they left it.
///
/// Keyed on [LessonSection.id] for the reason [ProgressStore] is. **Per
/// browser**, and a convenience rather than a record: every read and write
/// swallows its own failure.
///
/// Holds only code that differs from the starter block. A section the student
/// never changed has no entry, so a starter the author rewrites still reaches
/// them.
///
/// A change is in memory at once and in storage once typing pauses for
/// [writeDelay], or at the next [flush].
abstract class CodeDraftStoreBase with Store {

  /// How long typing has to pause before its drafts are written out.
  ///
  /// Browsers batch localStorage writes themselves, but Android's DataStore
  /// rewrites its whole file on every call, which per keystroke is needless
  /// wear on flash.
  static const Duration writeDelay = Duration(seconds: 1);

  /// One key per section. The language and lesson are part of it because a
  /// section id is only unique within its own lesson.
  static String keyFor(String language, String lessonId, String sectionId) => 'code.$language.$lessonId.$sectionId';

  /// One key per project, for the one program all of its tasks share.
  static String workKeyFor(String language, String lessonId) => 'work.$language.$lessonId';

  /// One key per task of a project, for the program as it stood when the
  /// student said the task worked.
  static String snapshotKeyFor(String language, String lessonId, String sectionId) =>
      'snapshot.$language.$lessonId.$sectionId';

  final SharedPreferencesAsync _preferences;

  /// Drafts by [keyFor]. Observable only so the settings menu can tell whether
  /// there is anything to clear.
  @readonly
  Map<String, String> _drafts = {};

  /// Changes not yet in storage, by [keyFor]. Null is a draft to remove.
  final Map<String, String?> _unwritten = {};

  Timer? _writeTimer;

  CodeDraftStoreBase({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  /// Reads the drafts of every section [course] has. Called once, by the
  /// initialization screen.
  ///
  /// A failure is swallowed: a browser that refuses storage MUST NOT keep the
  /// app from starting.
  Future<void> load(Course course) async {
    final keys = {
      for (final lesson in course.lessons)
        if (lesson.translations.values.first.isProject) ...[
          _workKeyIn(lesson),
          for (final section in lesson.translations.values.first.sections) _snapshotKeyIn(lesson, section.id),
        ] else
          for (final section in lesson.translations.values.first.sections) _keyIn(lesson, section.id),
    };

    try {
      final stored = await _preferences.getAll(allowList: keys);
      _replace({
        for (final MapEntry(:key, :value) in stored.entries)
          if (value is String) key: value,
      });
    } on Object {
      // Treated as "nothing saved".
    }
  }

  @computed
  bool get hasDrafts => _drafts.isNotEmpty;

  /// What the student last typed into [sectionId], or null when they never
  /// changed its starter block.
  String? codeFor(CourseLesson lesson, String sectionId) => _drafts[_keyIn(lesson, sectionId)];

  /// Keeps [code] as the draft of [sectionId].
  ///
  /// Returns at once when nothing changed, so a caller MAY call it on every
  /// notification an editor sends, a moved caret included.
  void keep(CourseLesson lesson, String sectionId, String code) => _put(_keyIn(lesson, sectionId), code);

  /// Drops the draft of [sectionId], so it opens on its starter block again.
  void forget(CourseLesson lesson, String sectionId) => _drop(_keyIn(lesson, sectionId));

  /// The program a project's tasks share, or null when the student never
  /// changed its starter block.
  String? workFor(CourseLesson lesson) => _drafts[_workKeyIn(lesson)];

  /// Keeps [code] as the program [lesson]'s tasks share. Returns at once when
  /// nothing changed, as [keep] does.
  void keepWork(CourseLesson lesson, String code) => _put(_workKeyIn(lesson), code);

  /// Drops the shared program, so the project opens on its starter block again.
  void forgetWork(CourseLesson lesson) => _drop(_workKeyIn(lesson));

  /// The program as it stood when the student said task [sectionId] worked, or
  /// null when they never did.
  String? snapshotFor(CourseLesson lesson, String sectionId) => _drafts[_snapshotKeyIn(lesson, sectionId)];

  /// Keeps [code] as task [sectionId]'s snapshot, replacing any before it.
  ///
  /// Unlike [keep], a starter block is kept too: the snapshot is what the
  /// program *was*, and a task that works with the starter untouched still
  /// worked.
  void keepSnapshot(CourseLesson lesson, String sectionId, String code) =>
      _put(_snapshotKeyIn(lesson, sectionId), code);

  void _put(String key, String code) {
    if (_drafts[key] == code) return;

    _replace({..._drafts, key: code});
    _schedule(key, code);
  }

  void _drop(String key) {
    if (!_drafts.containsKey(key)) return;

    _replace({..._drafts}..remove(key));
    _schedule(key, null);
  }

  /// Writes out every change still waiting on [writeDelay].
  ///
  /// A caller SHOULD flush when the student stops typing for a reason the delay
  /// cannot see coming, such as the app being hidden: a tab that closes takes
  /// the pending timer with it.
  Future<void> flush() async {
    _writeTimer?.cancel();
    _writeTimer = null;

    final unwritten = {..._unwritten};
    _unwritten.clear();

    for (final MapEntry(:key, :value) in unwritten.entries) {
      try {
        if (value == null) {
          await _preferences.remove(key);
        } else {
          await _preferences.setString(key, value);
        }
      } on Object {
        // Kept for this session either way.
      }
    }
  }

  /// Forgets every draft, in storage as well as in memory.
  Future<void> clear() async {
    _writeTimer?.cancel();
    _writeTimer = null;

    // Unwritten keys too: a draft forgotten since the last write is gone from
    // memory but still in storage.
    final keys = {..._drafts.keys, ..._unwritten.keys};
    _unwritten.clear();
    _replace({});

    for (final key in keys) {
      try {
        await _preferences.remove(key);
      } on Object {
        // Nothing to do about a storage that will not forget.
      }
    }
  }

  void _schedule(String key, String? code) {
    _unwritten[key] = code;
    _writeTimer?.cancel();
    _writeTimer = Timer(writeDelay, () => unawaited(flush()));
  }

  String _keyIn(CourseLesson lesson, String sectionId) =>
      keyFor(lesson.entry.language, lesson.translations.values.first.id, sectionId);

  String _workKeyIn(CourseLesson lesson) => workKeyFor(lesson.entry.language, lesson.translations.values.first.id);

  String _snapshotKeyIn(CourseLesson lesson, String sectionId) =>
      snapshotKeyFor(lesson.entry.language, lesson.translations.values.first.id, sectionId);

  @action
  void _replace(Map<String, String> value) => _drafts = value;

}
