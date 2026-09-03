import 'package:flutter/services.dart' show AssetBundle, AssetManifest, rootBundle;
import 'package:i_can_code/services/lessons/lesson.dart';

/// One lesson as it appears on disk, before it is read.
///
/// A lesson has one file per locale, all sharing an order prefix and a slug:
/// `assets/lessons/<language>/<order>-<slug>.<locale>.md`.
class LessonEntry {

  /// The programming language the lesson teaches — the directory it sits in.
  final String language;

  /// The `NN-` prefix. **The only source of course order** — there is no index
  /// file.
  final int order;

  /// The filename's `<order>-<slug>` part. Distinct from [Lesson.id], which the
  /// file states about itself.
  final String slug;

  /// Asset paths by locale code, e.g. `{'nl': '…/01-input-and-output.nl.md'}`.
  final Map<String, String> paths;

  const LessonEntry({
    required this.language,
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

  /// `assets/lessons/<language>/<order>-<slug>.<locale>.md`
  static final RegExp _filePattern = RegExp(r'^([a-z0-9_]+)/(\d+)-([a-z0-9-]+)\.([a-z]{2})\.md$');

  /// In course order: by programming language, then by the filename's prefix.
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
      lessons.add(CourseLesson(entry: entry, translations: translations));
    }

    return Course(lessons: lessons);
  }

  /// The programming languages the course teaches, in the order lessons are
  /// listed. One directory under [root] is one language.
  List<String> get languages {
    // `Set.add` answers whether the value was new, which keeps first-seen order
    // while deduplicating in one pass.
    final seen = <String>{};
    return [
      for (final lesson in lessons)
        if (seen.add(lesson.entry.language)) lesson.entry.language,
    ];
  }

  /// The lessons that teach [language], in course order.
  List<CourseLesson> lessonsFor(String language) =>
      lessons.where((lesson) => lesson.entry.language == language).toList();

  /// The lesson after [lesson] in its own language, or null when it is the last
  /// one. Course order is the filename's `NN-` prefix, so this follows a rename.
  ///
  /// Matched on [Lesson.id] rather than on identity, so it still answers for a
  /// lesson that came from a second parse of the same course.
  CourseLesson? lessonAfter(CourseLesson lesson) {
    final siblings = lessonsFor(lesson.entry.language);
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

      final language = match.group(1)!;
      final order = int.parse(match.group(2)!);
      final slug = match.group(3)!;
      final locale = match.group(4)!;

      final key = '$language/$order-$slug';
      grouped[key] = LessonEntry(
        language: language,
        order: order,
        slug: slug,
        paths: {...?grouped[key]?.paths, locale: asset},
      );
    }

    return grouped.values.toList()
      ..sort((a, b) {
        final byLanguage = a.language.compareTo(b.language);
        return byLanguage != 0 ? byLanguage : a.order.compareTo(b.order);
      });
  }

}

/// A programming language's name as a reader would write it. Derived from the
/// lower-case directory name; anything not simply capitalised — `csharp`, say —
/// needs a case here.
String languageLabel(String language) => switch (language) {
  'python' => 'Python',
  _ => language.isEmpty ? language : language[0].toUpperCase() + language.substring(1),
};

/// The emoji on a language's card, or null for one this table does not name.
///
/// A language is a directory, so unlike a lesson it has no file to carry its
/// own. A new language MAY be added without touching this — the card falls back
/// to the initial [languageLabel] gives it.
String? languageEmoji(String language) => switch (language) {
  'python' => '🐍',
  _ => null,
};

/// The URL segment a language's pages live under: `python` -> `learn-python`.
/// MUST stay in step with [languageFromSlug], which is its inverse.
String languageSlug(String language) => 'learn-$language';

/// The language a [slug] names, or null if it is not one of ours.
String? languageFromSlug(String slug) => slug.startsWith(_slugPrefix) ? slug.substring(_slugPrefix.length) : null;

const String _slugPrefix = 'learn-';
