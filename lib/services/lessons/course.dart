import 'package:flutter/services.dart' show AssetBundle, AssetManifest, rootBundle;
import 'package:i_can_code/services/lessons/lesson.dart';

/// One lesson as it appears on disk, before it is read.
///
/// A lesson has one file per locale, all sharing an order prefix and a slug:
/// `assets/lessons/<subject>/<order>-<slug>.<locale>.md`, or one folder deeper
/// in a [track].
class LessonEntry {

  /// The subject the lesson teaches — the directory it sits in.
  final String subject;

  /// The folder inside the subject's directory that holds the lesson, or null
  /// for a lesson directly in it.
  ///
  /// A track is numbered on its own and listed after the lessons outside it, so
  /// a run of lessons can start again at `00-` without renumbering the course.
  final String? track;

  /// The `NN-` prefix. **The only source of course order** — there is no index
  /// file.
  final int order;

  /// The filename's `<order>-<slug>` part. Distinct from [Lesson.id], which the
  /// file states about itself.
  final String slug;

  /// Asset paths by locale code, e.g. `{'nl': '…/01-uitvoer.nl.md'}`.
  final Map<String, String> paths;

  const LessonEntry({
    required this.subject,
    this.track,
    required this.order,
    required this.slug,
    required this.paths,
  });

  /// The locales this lesson has been translated into.
  Iterable<String> get locales => paths.keys;

}

/// One lesson, parsed in every locale it has been translated into.
///
/// All translations are parsed up front so the header's language toggle
/// re-titles the catalog with no reload and no loading state.
class CourseLesson {

  final LessonEntry entry;

  /// The parsed lesson by locale code. Never empty.
  final Map<String, Lesson> translations;

  const CourseLesson({required this.entry, required this.translations});

  /// The lesson in [locale], falling back to English and then to whichever
  /// translation exists.
  Lesson forLocale(String locale) =>
      translations[locale] ?? translations['en'] ?? translations.values.first;

}

/// Every lesson the app ships with, discovered and parsed.
///
/// There is no index file: Flutter's [AssetManifest] lists what was bundled, so
/// the directory *is* the index and reordering the course is a rename. Order and
/// locale therefore come out of the filename, and anything not matching
/// [_filePattern] is ignored rather than crashing the app.
class Course {

  static const String root = 'assets/lessons/';

  /// `assets/lessons/<subject>/[<track>/]<order>-<slug>.<locale>.md`
  static final RegExp _filePattern = RegExp(
    r'^([a-z0-9_]+)/(?:([a-z0-9_-]+)/)?(\d+)-([a-z0-9-]+)\.([a-z]{2})\.md$',
  );

  /// In course order: by subject, then the lessons outside any
  /// track before each track in turn, then by the filename's prefix.
  final List<CourseLesson> lessons;

  const Course({required this.lessons});

  /// Discovers every lesson file and parses each translation.
  ///
  /// A malformed lesson throws — see [Lesson.parse]. These files ship with the
  /// app, so that is a build mistake, not a state to render.
  static Future<Course> load({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(assets);

    final lessons = <CourseLesson>[];
    for (final entry in entriesFrom(manifest.listAssets())) {
      final translations = <String, Lesson>{};
      for (final MapEntry(key: locale, value: path) in entry.paths.entries) {
        try {
          translations[locale] = Lesson.parse(await assets.loadString(path));
        } on FormatException catch (error) {
          throw FormatException('$path: ${error.message}');
        }
      }
      // A lesson whose steps all need a runtime this version cannot run parses
      // to no steps at all (see [LessonRuntime.isReady]). It is left out rather
      // than listed as a card that opens on nothing, and a course may carry one
      // before the app can run it. Any locale, not every: a card that opens in
      // one language and not in another is worse than no card.
      if (translations.values.any((lesson) => lesson.sections.isEmpty)) continue;
      lessons.add(CourseLesson(entry: entry, translations: translations));
    }

    return Course(lessons: lessons);
  }

  /// The subjects the course teaches, in the order lessons are
  /// listed. One directory under [root] is one subject.
  List<String> get subjects {
    // `Set.add` answers whether the value was new, which keeps first-seen order
    // while deduplicating in one pass.
    final seen = <String>{};
    return [
      for (final lesson in lessons)
        if (seen.add(lesson.entry.subject)) lesson.entry.subject,
    ];
  }

  /// The lessons that teach [subject], in course order.
  List<CourseLesson> lessonsFor(String subject) =>
      lessons.where((lesson) => lesson.entry.subject == subject).toList();

  /// The lesson after [lesson] in its own subject, or null when it is the last
  /// one. Course order is the filename's `NN-` prefix, so this follows a rename.
  ///
  /// Matched on [Lesson.id] rather than on identity, so it still answers for a
  /// lesson that came from a second parse of the same course.
  CourseLesson? lessonAfter(CourseLesson lesson) {
    final siblings = lessonsFor(lesson.entry.subject);
    final id = lesson.translations.values.first.id;
    final index = siblings.indexWhere((sibling) => sibling.translations.values.first.id == id);

    return index == -1 || index + 1 == siblings.length ? null : siblings[index + 1];
  }

  /// Groups asset paths into lessons. Separate from [load] so the naming rules
  /// are testable without an asset bundle.
  static List<LessonEntry> entriesFrom(Iterable<String> assets) {
    final grouped = <String, LessonEntry>{};

    for (final asset in assets) {
      if (!asset.startsWith(root)) continue;
      final match = _filePattern.firstMatch(asset.substring(root.length));
      if (match == null) continue;

      final subject = match.group(1)!;
      final track = match.group(2);
      final order = int.parse(match.group(3)!);
      final slug = match.group(4)!;
      final locale = match.group(5)!;

      final key = '$subject/${track ?? ''}/$order-$slug';
      grouped[key] = LessonEntry(
        subject: subject,
        track: track,
        order: order,
        slug: slug,
        paths: {...?grouped[key]?.paths, locale: asset},
      );
    }

    return grouped.values.toList()
      ..sort((a, b) {
        final bySubject = a.subject.compareTo(b.subject);
        if (bySubject != 0) return bySubject;
        // The empty name sorts first, which puts the lessons outside any track
        // ahead of every track.
        final byTrack = (a.track ?? '').compareTo(b.track ?? '');
        return byTrack != 0 ? byTrack : a.order.compareTo(b.order);
      });
  }

}

/// A subject's name as a reader would write it. Derived from the
/// lower-case directory name; anything not simply capitalised — `csharp`, say —
/// needs a case here.
String subjectLabel(String subject) => switch (subject) {
  'python' => 'Python',
  _ => subject.isEmpty ? subject : subject[0].toUpperCase() + subject.substring(1),
};

/// The emoji on a subject's card, or null for one this table does not name.
///
/// A subject is a directory, so unlike a lesson it has no file to carry its
/// own. A new subject MAY be added without touching this — the card falls back
/// to the initial [subjectLabel] gives it.
String? subjectEmoji(String subject) => switch (subject) {
  'python' => '🐍',
  _ => null,
};

/// Whether this subject has an interactive console to offer beside its
/// lessons, which is what puts an "Extra" section on its catalog.
///
/// A fact about the runtime, not about the lessons: it is true where a subject
/// has a REPL the app can host, and a subject whose lessons exist without one
/// simply has no Extra section.
bool subjectHasRepl(String subject) => subject == 'python';

/// Whether this subject's code can be put on a micro:bit, which is the other thing an
/// "Extra" section offers.
///
/// True for Python because the board runs MicroPython. A fact about what the
/// hardware speaks, not about the lessons — the lessons stay browser-only.
bool subjectHasMicrobit(String subject) => subject == 'python';

/// How many spaces a Tab indents by in this subject's code editor.
///
/// Four for Python, as its style guide asks:
/// https://peps.python.org/pep-0008/#indentation. A subject this table does
/// not name gets two, which is what `re_editor` uses when it is told nothing.
int subjectIndentSize(String subject) => switch (subject) {
  'python' => 4,
  _ => 2,
};

/// The URL segment a subject's pages live under: `python` -> `learn-python`.
/// MUST stay in step with [subjectFromSlug], which is its inverse.
String subjectSlug(String subject) => 'learn-$subject';

/// The subject a [slug] names, or null if it is not one of ours.
String? subjectFromSlug(String slug) => slug.startsWith(_slugPrefix) ? slug.substring(_slugPrefix.length) : null;

const String _slugPrefix = 'learn-';
