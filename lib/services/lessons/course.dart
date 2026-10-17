import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/lessons/subject_contents.dart';

/// A heading in a subject's contents, over the lessons listed under it.
class LessonGroup {

  /// From the heading's `{#id}`. Shared by every locale, which the heading's
  /// own words are not.
  final String id;

  /// The heading by locale code. Never empty.
  final Map<String, String> titles;

  /// The feature toggle that has to be on for the group and every lesson under
  /// it to be shown, or null for a group that is always shown. The same in
  /// every locale.
  final String? feature;

  const LessonGroup({required this.id, required this.titles, this.feature});

  /// The heading in [locale], falling back the way [CourseLesson.forLocale]
  /// does.
  String titleFor(String locale) => titles[locale] ?? titles['en'] ?? titles.values.first;

}

/// One lesson as its subject's contents list it, before it is read.
///
/// A lesson has one file per locale. Which files those are, and where the
/// lesson stands, is what each `contents.<locale>.md` says: see
/// [SubjectContents].
class LessonEntry {

  /// The subject the lesson teaches — the directory its contents file sits in.
  final String subject;

  /// The heading the lesson is listed under, or null for a lesson under none.
  final LessonGroup? group;

  /// Where the lesson stands in its subject's contents, counted from 1. **The
  /// contents file is the only source of course order.**
  final int order;

  /// The lesson's files by locale code, e.g. `{'nl': '…/week-1/01-uitvoer.nl.md'}`.
  /// Each is a key of the bundle [Course.load] reads.
  final Map<String, String> paths;

  /// What each locale's contents file calls the lesson. The app shows the
  /// lesson's own title; `test/content/lessons_test.dart` holds the two equal.
  final Map<String, String> listedTitles;

  const LessonEntry({
    required this.subject,
    this.group,
    required this.order,
    required this.paths,
    this.listedTitles = const {},
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

  /// Every feature toggle that has to be on for this lesson to be shown: its
  /// group's and its own. Empty for a lesson that is always shown.
  Set<String> get features => {?entry.group?.feature, ?translations.values.first.feature};

}

/// Every lesson the app ships with, discovered and parsed.
///
/// A subject is a directory under [root], and its `contents.<locale>.md` files
/// say which lessons it has, in what order and under which headings. Where a
/// lesson's file sits inside that directory, and what it is called, means
/// nothing.
class Course {

  static const String root = 'assets/lessons/';

  /// The one asset that holds every lesson file: a JSON object of file text by
  /// path under [root]. Written by `bin/bundle_lessons.dart` during the build,
  /// so a cold start fetches the course in one request.
  static const String bundleAsset = 'assets/course.json';

  /// `<subject>/contents.<locale>.md`, under [root].
  static final RegExp _contentsPattern = RegExp(r'^([a-z0-9_]+)/contents\.([a-z]{2})\.md$');

  /// Any markdown file inside a subject's directory, at any depth.
  static final RegExp _subjectFilePattern = RegExp(r'^([a-z0-9_]+)/.+\.md$');

  /// Whether [path], a key of the bundle, is a subject's contents file.
  static bool isContents(String path) =>
      path.startsWith(root) && _contentsPattern.hasMatch(path.substring(root.length));

  /// Whether [path], a key of the bundle, is a markdown file in a subject's
  /// directory: a lesson, a contents file, or a part of either.
  static bool isInSubject(String path) =>
      path.startsWith(root) && _subjectFilePattern.hasMatch(path.substring(root.length));

  /// In course order: by subject, then as that subject's contents list them.
  final List<CourseLesson> lessons;

  const Course({required this.lessons});

  /// Reads [bundleAsset] and parses each translation of every lesson in it.
  ///
  /// A malformed lesson or contents file throws — see [fromFiles]. These files
  /// ship with the app, so that is a build mistake, not a state to render.
  static Future<Course> load({AssetBundle? bundle}) async {
    // Not cached: the bundle is every lesson's text, and it is read once.
    final source = await (bundle ?? rootBundle).loadString(bundleAsset, cache: false);

    return fromFiles((jsonDecode(source) as Map<String, dynamic>).cast<String, String>());
  }

  /// The course [files] hold: file text by path under [root], with every
  /// include already resolved.
  ///
  /// Throws a [FormatException] naming the file when a lesson or a contents
  /// file is malformed, and when two locales' contents files put a different
  /// lesson in the same place.
  static Course fromFiles(Map<String, String> files) {
    final lessons = <CourseLesson>[];
    for (final entry in entriesFrom(files)) {
      final translations = <String, Lesson>{};
      for (final MapEntry(key: locale, value: path) in entry.paths.entries) {
        try {
          translations[locale] = Lesson.parse(files[path]!);
        } on FormatException catch (error) {
          throw FormatException('$path: ${error.message}');
        }
      }

      // Translations are paired by where the contents files list them, so only
      // the id can tell that two of them are the same lesson.
      final first = translations.values.first;
      for (final MapEntry(key: locale, value: lesson) in translations.entries) {
        if (lesson.id != first.id) {
          throw FormatException(
            '${entry.paths[locale]} is "${lesson.id}" where ${entry.paths.values.first} is "${first.id}". '
            'Every contents file of a subject lists the same lessons in the same order.',
          );
        }
        // One translation shown and another hidden would put a lesson in the
        // catalog in one language and not in the other.
        if (lesson.feature != first.feature) {
          throw FormatException(
            '${entry.paths[locale]} names the feature ${lesson.feature ?? 'none'} '
            'where ${entry.paths.values.first} names ${first.feature ?? 'none'}.',
          );
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

  /// Every feature toggle the course names, on a lesson or on a group, sorted.
  List<String> get features => (lessons.expand((lesson) => lesson.features).toSet().toList()..sort());

  /// The part of this course [isOn] lets through: the lessons whose every
  /// feature toggle is on, which includes every lesson that names none.
  Course visibleWith(bool Function(String feature) isOn) =>
      Course(lessons: [for (final lesson in lessons) if (lesson.features.every(isOn)) lesson]);

  /// The lesson after [lesson] in its own subject that [isOn] lets through, or
  /// null when there is none. Course order is the contents file's, so this
  /// follows a reorder there.
  ///
  /// [lesson] itself need not be let through: a hidden lesson opened by its
  /// address still leads on to the next one that is shown. Matched on
  /// [Lesson.id] rather than on identity, so it still answers for a lesson that
  /// came from a second parse of the same course.
  CourseLesson? lessonAfter(CourseLesson lesson, {bool Function(String feature)? isOn}) {
    final siblings = lessonsFor(lesson.entry.subject);
    final id = lesson.translations.values.first.id;
    final index = siblings.indexWhere((sibling) => sibling.translations.values.first.id == id);
    if (index == -1) return null;

    return siblings.skip(index + 1).where((sibling) => isOn == null || sibling.features.every(isOn)).firstOrNull;
  }

  /// The lessons [files] hold, as their subjects' contents files list them.
  /// Separate from [fromFiles] so the structure is testable without a lesson
  /// that parses.
  ///
  /// [files] is file text by path, and only the paths under [root] count. The
  /// text matters for the contents files alone: of a lesson, only that its
  /// path is there.
  ///
  /// Throws a [FormatException] when a contents file is malformed or lists a
  /// file that is not in [files], when a subject's contents files do not all
  /// have the same shape, and when a subject has markdown files and no
  /// contents file to list them.
  static List<LessonEntry> entriesFrom(Map<String, String> files) {
    // Both sorted: by subject for the order of the course, and by locale so
    // "the first translation" is the same one on every run.
    final contents = SplayTreeMap<String, SplayTreeMap<String, SubjectContents>>();

    for (final MapEntry(key: path, value: text) in files.entries) {
      if (!path.startsWith(root)) continue;
      final match = _contentsPattern.firstMatch(path.substring(root.length));
      if (match == null) continue;

      try {
        (contents[match.group(1)!] ??= SplayTreeMap())[match.group(2)!] = SubjectContents.parse(text);
      } on FormatException catch (error) {
        throw FormatException('$path: ${error.message}');
      }
    }

    // Without this a subject that was never given a contents file would be an
    // empty catalog rather than a failed build.
    for (final path in files.keys) {
      if (!path.startsWith(root)) continue;
      final subject = _subjectFilePattern.firstMatch(path.substring(root.length))?.group(1);
      if (subject != null && !contents.containsKey(subject)) {
        throw FormatException('$root$subject holds $path and no contents.<locale>.md to list it in.');
      }
    }

    return [
      for (final MapEntry(key: subject, value: byLocale) in contents.entries) ..._entriesOf(subject, byLocale, files),
    ];
  }

  /// One subject's lessons, from its contents file in every locale.
  static List<LessonEntry> _entriesOf(
    String subject,
    Map<String, SubjectContents> byLocale,
    Map<String, String> files,
  ) {
    String contentsPath(String locale) => '$root$subject/contents.$locale.md';

    final MapEntry(key: firstLocale, value: first) = byLocale.entries.first;
    for (final MapEntry(key: locale, value: other) in byLocale.entries.skip(1)) {
      if (other.items.length != first.items.length) {
        throw FormatException(
          '${contentsPath(locale)} lists ${other.items.length} lessons '
          'where ${contentsPath(firstLocale)} lists ${first.items.length}.',
        );
      }
      for (final (index, item) in other.items.indexed) {
        if (item.group?.id != first.items[index].group?.id) {
          throw FormatException(
            '${contentsPath(locale)} lists "${item.title}" under a different group '
            'than ${contentsPath(firstLocale)} lists "${first.items[index].title}".',
          );
        }
        if (item.group?.feature != first.items[index].group?.feature) {
          throw FormatException(
            '${contentsPath(locale)} gives the group of "${item.title}" a different feature '
            'than ${contentsPath(firstLocale)} gives it.',
          );
        }
      }
    }

    final groups = <String, LessonGroup>{};
    final entries = <LessonEntry>[];

    for (final (index, item) in first.items.indexed) {
      final paths = <String, String>{};
      for (final MapEntry(key: locale, value: translated) in byLocale.entries) {
        final path = '$root$subject/${translated.items[index].path}';
        if (!files.containsKey(path)) {
          throw FormatException('${contentsPath(locale)} lists ${translated.items[index].path}, which does not exist.');
        }
        paths[locale] = path;
      }

      entries.add(
        LessonEntry(
          subject: subject,
          group: switch (item.group) {
            null => null,
            final group => groups[group.id] ??= LessonGroup(
              id: group.id,
              feature: group.feature,
              titles: {
                for (final MapEntry(key: locale, value: translated) in byLocale.entries)
                  locale: translated.items[index].group!.title,
              },
            ),
          },
          order: index + 1,
          paths: paths,
          listedTitles: {
            for (final MapEntry(key: locale, value: translated) in byLocale.entries)
              locale: translated.items[index].title,
          },
        ),
      );
    }

    return entries;
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
/// A subject's contents files list its lessons and say nothing about the
/// subject, so unlike a lesson it has no file to carry its own. A new subject
/// MAY be added without touching this — the card falls back to the initial
/// [subjectLabel] gives it.
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
