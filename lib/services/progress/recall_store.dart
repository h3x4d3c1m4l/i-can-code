import 'dart:convert';

import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:mobx/mobx.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'recall_store.g.dart';

/// Where a finished lesson stands on the refresher ladder: the next rung, and
/// when it comes up.
typedef RecallEntry = ({DateTime due, int rung});

class RecallStore = RecallStoreBase with _$RecallStore;

/// When a finished lesson is worth asking about again.
///
/// The reason this exists rather than the app simply offering everything at
/// once: a test taken **minutes** after reading measures working memory, and
/// one taken a day later measures what was retained. Toppino & Cohen (2009)
/// found no difference at all between tested and re-studied material after a
/// few minutes, and a clear one after a few days. Cepeda et al. (2008) put a
/// number on the gap — the best spacing is roughly 10–20% of how long you want
/// to remember something, so **12 to 24 hours to still know it a week later**.
/// That is where the first rung's day comes from; it is not a round number
/// somebody liked.
///
/// Three things it deliberately is **not**:
///
/// - **Not a lock.** The day decides when the app *asks*, never when the student
///   *may*: a refresher can always be started early, and nothing is greyed out
///   behind a countdown. An app that is otherwise entirely open should not grow
///   one closed door.
/// - **Not a record**, exactly like [ProgressStore]: per browser, never per
///   person, and every read and write swallows its own failure. A missing or
///   unreadable entry **fails open** — the lesson is offered rather than
///   silently never offered again, which is the failure nobody would notice.
/// - **Not a punishment.** A refresher that goes badly moves a lesson back a
///   rung. It never takes away a tick: progress stays monotonic, and nothing
///   here is graded.
abstract class RecallStoreBase with Store {

  /// One key per lesson, beside `ProgressStore`'s. The language is part of it
  /// because a lesson id is only unique within its own language directory.
  static String keyFor(String language, String lessonId) => 'recall.$language.$lessonId';

  /// How long after the last success each rung comes up.
  ///
  /// Two rungs, not three. A 7-day rung is where the evidence points next, but
  /// **Safari and iOS delete all script-writable storage after 7 days without a
  /// visit** — the exact student it would be aimed at is the one whose schedule
  /// is already gone. It is left out rather than shipped as something that
  /// quietly never fires.
  static const List<Duration> ladder = [Duration(days: 1), Duration(days: 3)];

  final SharedPreferencesAsync _preferences;

  /// The clock, injected so a test can stand a day later without waiting one.
  final DateTime Function() _now;

  /// What is scheduled, by [keyFor]. Observable, so a refresher that falls due
  /// while the catalog is open appears on it.
  @readonly
  Map<String, RecallEntry> _scheduled = {};

  RecallStoreBase({SharedPreferencesAsync? preferences, DateTime Function()? now})
    : _preferences = preferences ?? SharedPreferencesAsync(),
      _now = now ?? DateTime.now;

  /// Reads what was saved. Called once, by the initialization screen.
  ///
  /// A failure is swallowed, and an entry that will not parse is dropped: both
  /// leave the lesson with no entry, which reads as due. See the note on the
  /// class about failing open.
  Future<void> load(Course course) async {
    final loaded = <String, RecallEntry>{};

    for (final lesson in course.lessons) {
      final key = _keyOf(lesson);
      try {
        if (await _preferences.getString(key) case final String stored) {
          if (_decode(stored) case final RecallEntry entry) loaded[key] = entry;
        }
      } on Object {
        // Treated as "nothing scheduled for this lesson", which is due.
      }
    }

    _replace(loaded);
  }

  RecallEntry? entryFor(CourseLesson lesson) => _scheduled[_keyOf(lesson)];

  /// Whether [lesson] is worth asking about again now.
  ///
  /// **A lesson with no entry is due.** That is the fail-open rule: storage that
  /// was cleared, refused or written before this existed must not turn the
  /// refresher off for good.
  ///
  /// This says nothing about whether the lesson was ever finished — that is
  /// [ProgressStore]'s to answer, and the caller combines the two.
  bool isDue(CourseLesson lesson) {
    final entry = entryFor(lesson);
    if (entry == null) return true;
    if (entry.rung >= ladder.length) return false;

    return !entry.due.isAfter(_now());
  }

  /// Puts [lesson] on the first rung, a day out.
  ///
  /// Called the moment a lesson is finished. Does nothing to a lesson that is
  /// already on the ladder, so finishing a step of an already-finished lesson
  /// does not push its refresher away again.
  Future<void> schedule(CourseLesson lesson) async {
    if (_scheduled.containsKey(_keyOf(lesson))) return;

    await _write(lesson, (due: _now().add(ladder.first), rung: 0));
  }

  /// The refresher went well: up a rung, and out to the next interval.
  ///
  /// Past the last rung the lesson settles — [isDue] stops offering it, and the
  /// entry stays so that a later course change does not make it due again.
  Future<void> advance(CourseLesson lesson) async {
    final rung = (entryFor(lesson)?.rung ?? 0) + 1;
    final wait = rung < ladder.length ? ladder[rung] : ladder.last;

    await _write(lesson, (due: _now().add(wait), rung: rung));
  }

  /// The refresher went badly: back a rung, and round again sooner.
  ///
  /// Never below the first rung, and it takes nothing away — a lesson stays
  /// finished, ticked and countable. The only thing that changes is how soon it
  /// is asked about again.
  Future<void> hold(CourseLesson lesson) async {
    final rung = ((entryFor(lesson)?.rung ?? 0) - 1).clamp(0, ladder.length - 1);

    await _write(lesson, (due: _now().add(ladder[rung]), rung: rung));
  }

  /// Forgets every schedule, in storage as well as in memory. Called beside
  /// `ProgressStore.clear`, because a refresher for a lesson nobody has done is
  /// not something to keep.
  Future<void> clear() async {
    for (final key in _scheduled.keys) {
      try {
        await _preferences.remove(key);
      } on Object {
        // Nothing to do about a storage that will not forget.
      }
    }
    _replace({});
  }

  Future<void> _write(CourseLesson lesson, RecallEntry entry) async {
    final key = _keyOf(lesson);
    _replace({..._scheduled, key: entry});

    try {
      await _preferences.setString(key, jsonEncode({'due': entry.due.toIso8601String(), 'rung': entry.rung}));
    } on Object {
      // The schedule stands for this session either way.
    }
  }

  static String _keyOf(CourseLesson lesson) =>
      keyFor(lesson.entry.language, lesson.translations.values.first.id);

  /// Null for anything that will not read back as an entry, which is treated as
  /// nothing saved.
  static RecallEntry? _decode(String stored) {
    try {
      final map = jsonDecode(stored);
      if (map is! Map) return null;

      final due = DateTime.tryParse(map['due'] as String? ?? '');
      final rung = map['rung'];
      if (due == null || rung is! int || rung < 0) return null;

      return (due: due, rung: rung);
    } on Object {
      return null;
    }
  }

  @action
  void _replace(Map<String, RecallEntry> value) => _scheduled = value;

}

/// One thing to do again: a section, and the lesson it belongs to.
typedef RecallItem = ({CourseLesson lesson, LessonSection section});

/// What a refresher asks, drawn from lessons that are due.
///
/// **Only sections whose answer the student produces from nothing**: the two
/// that ask for code, and the one that asks what a program prints. Dunlosky et
/// al. (2013) are unambiguous about test format — practice that requires a
/// *generative* answer beats filling a blank, which beats recognising. A board
/// of tiles is the bottom of that ladder and makes a poor measure of what was
/// retained, so a refresher is built from the top of it.
///
/// `orderLines` is left out for the same reason, though it is a near thing: its
/// lines are handed to the student, so it is recognition wearing a puzzle's
/// clothes.
///
/// **Interleaved, round robin.** Items alternate between lessons rather than
/// working through one and then the next; mixing problem types is worth about
/// 43% more accuracy a week on (Dunlosky et al., 2013).
///
/// The caller passes only lessons that are both finished and due — being
/// finished is `ProgressStore`'s to say and being due is [RecallStore]'s, and
/// neither belongs in here.
bool _worthRecalling(SectionKind kind) => kind.isAssignment || kind == SectionKind.predictOutput;

List<RecallItem> recallSession(List<CourseLesson> due, {int limit = 5}) {
  final perLesson = [
    for (final lesson in due)
      [
        for (final section in lesson.translations.values.first.sections)
          if (_worthRecalling(section.kind)) (lesson: lesson, section: section),
      ],
  ];

  final items = <RecallItem>[];
  for (var round = 0; items.length < limit; round++) {
    var placed = false;
    for (final lesson in perLesson) {
      if (round >= lesson.length) continue;
      items.add(lesson[round]);
      placed = true;
      if (items.length == limit) break;
    }
    if (!placed) break;
  }

  return items;
}
