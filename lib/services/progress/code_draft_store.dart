import 'dart:async';

import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'code_draft_store.g.dart';

class CodeDraftStore = CodeDraftStoreBase with _$CodeDraftStore;

/// What a student last typed into each exercise, and on each page with an
/// editor of its own, so a reload or a later visit finds their code where they
/// left it.
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

  /// One key per section. The subject and lesson are part of it because a
  /// section id is only unique within its own lesson.
  static String keyFor(String subject, String lessonId, String sectionId) =>
      '$_codePrefix$subject.$lessonId.$sectionId';

  /// One key per project, for the one program all of its tasks share.
  static String workKeyFor(String subject, String lessonId) => '$_workPrefix$subject.$lessonId';

  /// One key per task of a project, for the program as it stood when the
  /// student said the task worked.
  static String snapshotKeyFor(String subject, String lessonId, String sectionId) =>
      '$_snapshotPrefix$subject.$lessonId.$sectionId';

  static const String _codePrefix = 'code.';
  static const String _workPrefix = 'work.';
  static const String _snapshotPrefix = 'snapshot.';
  static const String _pagePrefix = 'draft.';

  /// One key per page that is not a lesson. [page] MUST name the page and what
  /// it is about, such as `tkinter.python`, so two pages never share a draft.
  static String pageKeyFor(String page) => '$_pagePrefix$page';

  final SharedPreferencesAsync _preferences;

  /// Drafts by [keyFor]. Observable only so the settings menu can tell whether
  /// there is anything to clear.
  @readonly
  Map<String, String> _drafts = {};

  /// Whether storage holds code [load] did not read back: a lesson or section
  /// renamed or removed since leaves its old key behind. Nothing shows it, but
  /// a [clear] still has something to clear.
  @readonly
  bool _hasUnlisted = false;

  /// Changes not yet in storage, by [keyFor]. Null is a draft to remove.
  final Map<String, String?> _unwritten = {};

  Timer? _writeTimer;

  CodeDraftStoreBase({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  /// Reads the drafts of every section [course] has, and of every page. Called
  /// once, by the initialization screen.
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
      final storedKeys = await _storedKeys();
      // No course names a page, so a page's draft is read because it is there.
      final listed = {...keys, ...storedKeys.where((key) => key.startsWith(_pagePrefix))};
      final stored = await _preferences.getAll(allowList: listed);
      _reset({
        for (final MapEntry(:key, :value) in stored.entries)
          if (value is String) key: value,
      }, hasUnlisted: storedKeys.difference(listed).isNotEmpty);
    } on Object {
      // Treated as "nothing saved".
    }
  }

  /// Whether there is anything to clear. Counts code no section shows any
  /// more too.
  @computed
  bool get hasDrafts => _hasUnlisted || _drafts.isNotEmpty;

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

  /// What the student last typed on [page], a page that is not a lesson, or
  /// null when they never changed what it opened with.
  String? pageCodeFor(String page) => _drafts[pageKeyFor(page)];

  /// Keeps [code] as [page]'s draft. Returns at once when nothing changed, as
  /// [keep] does.
  void keepPage(String page, String code) => _put(pageKeyFor(page), code);

  /// Drops [page]'s draft, so it opens on what it started with again.
  void forgetPage(String page) => _drop(pageKeyFor(page));

  /// Whether any code of [lesson] is kept: a step's draft, a project's program
  /// or a task's snapshot.
  bool hasCodeIn(CourseLesson lesson) => _drafts.keys.any((key) => _isIn(lesson, key));

  /// Drops all of [lesson]'s code, so every step opens on its starter block
  /// again, and writes that out at once.
  Future<void> forgetLesson(CourseLesson lesson) async {
    for (final key in _drafts.keys.where((key) => _isIn(lesson, key)).toList()) {
      _drop(key);
    }
    await flush();
  }

  /// Whether [key] is one of [lesson]'s. The section keys end the lesson id in
  /// a dot, so `loops` does not claim the code of `loops-2`.
  bool _isIn(CourseLesson lesson, String key) {
    final subject = lesson.entry.subject;
    final id = lesson.translations.values.first.id;
    return key.startsWith('$_codePrefix$subject.$id.') ||
        key.startsWith('$_snapshotPrefix$subject.$id.') ||
        key == workKeyFor(subject, id);
  }

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

  /// Forgets every draft, in storage as well as in memory, including code of
  /// sections the course no longer has.
  Future<void> clear() async {
    _writeTimer?.cancel();
    _writeTimer = null;

    // Unwritten keys too: a draft forgotten since the last write is gone from
    // memory but still in storage.
    final keys = {..._drafts.keys, ..._unwritten.keys, ...await _storedKeys()};
    _unwritten.clear();
    _reset({}, hasUnlisted: false);

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
      keyFor(lesson.entry.subject, lesson.translations.values.first.id, sectionId);

  String _workKeyIn(CourseLesson lesson) => workKeyFor(lesson.entry.subject, lesson.translations.values.first.id);

  String _snapshotKeyIn(CourseLesson lesson, String sectionId) =>
      snapshotKeyFor(lesson.entry.subject, lesson.translations.values.first.id, sectionId);

  /// Every key in storage this store writes, read or not.
  Future<Set<String>> _storedKeys() async {
    try {
      return {
        ...(await _preferences.getKeys()).where(
          (key) =>
              key.startsWith(_codePrefix) ||
              key.startsWith(_workPrefix) ||
              key.startsWith(_snapshotPrefix) ||
              key.startsWith(_pagePrefix),
        ),
      };
    } on Object {
      return const {};
    }
  }

  @action
  void _replace(Map<String, String> value) => _drafts = value;

  @action
  void _reset(Map<String, String> drafts, {required bool hasUnlisted}) {
    _drafts = drafts;
    _hasUnlisted = hasUnlisted;
  }

}
