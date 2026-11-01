import 'dart:convert';

import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';

/// Which steps a student has finished, as a file they can take to another
/// browser.
///
/// Holds the ticks and what a report on them needs, a step's type and whether it
/// is optional, and no code or settings. Lessons and steps are named by id for
/// the reason [ProgressStore] keys on them, and by no locale, because every
/// translation shares them.
class ProgressFile {

  /// What a file says it is, so any other JSON file is refused as not being one.
  static const String format = 'i-can-code/progress';

  /// The version this app writes, and the newest it reads.
  ///
  /// A reader ignores fields it does not know, so a new field needs no new
  /// version. One that changes the meaning of a field already there does.
  static const int version = 1;

  /// The id [lesson] has in the file. The subject is part of it because a lesson
  /// id is only unique within its subject. A reader MUST treat it as opaque.
  static String lessonIdOf(CourseLesson lesson) => '${lesson.entry.subject}/${lesson.translations.values.first.id}';

  /// The finished step ids by [lessonIdOf], as the file lists them. A step the
  /// file says is not done is not in it, and neither is a lesson with none done.
  final Map<String, Set<String>> finished;

  const ProgressFile(this.finished);

  /// Reads [source], refusing all of it when any part does not hold.
  ///
  /// Throws a [ProgressFileException].
  factory ProgressFile.parse(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      throw const ProgressFileException(ProgressFileProblem.notProgress);
    }

    if (json is! Map || json['format'] != format) throw const ProgressFileException(ProgressFileProblem.notProgress);

    // Checked before the rest, which a newer version may have reshaped.
    final fileVersion = json['version'];
    if (fileVersion is! int || fileVersion < 1) throw const ProgressFileException(ProgressFileProblem.damaged);
    if (fileVersion > version) throw const ProgressFileException(ProgressFileProblem.newer);

    final lessons = json['lessons'];
    if (lessons is! List) throw const ProgressFileException(ProgressFileProblem.damaged);

    final finished = <String, Set<String>>{};
    for (final lesson in lessons) {
      if (lesson case {'id': final String id, 'steps': final List<Object?> steps}) {
        final done = finished.putIfAbsent(id, () => {});
        for (final step in steps) {
          if (step case {'id': final String stepId, 'done': final bool isDone}) {
            if (isDone) done.add(stepId);
          } else {
            throw const ProgressFileException(ProgressFileProblem.damaged);
          }
        }
      } else {
        throw const ProgressFileException(ProgressFileProblem.damaged);
      }
    }

    return ProgressFile(finished..removeWhere((_, steps) => steps.isEmpty));
  }

  /// Writes every lesson of [course] that [isOn] lets through, and every other
  /// one with a finished step, with each step it has now and whether it is
  /// done. Without [isOn] every lesson is written.
  ///
  /// The lessons with nothing done are there for a report on the file; an
  /// import reads only what is done.
  static String write(
    Course course,
    ProgressStore progress, {
    bool Function(String feature)? isOn,
    required DateTime exportedAt,
    String? appVersion,
  }) {
    final json = {
      'format': format,
      'version': version,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'appVersion': ?appVersion,
      'lessons': [
        for (final lesson in course.lessons)
          if (isOn == null || lesson.features.every(isOn) || progress.isStarted(lesson)) _lessonJson(lesson, progress),
      ],
    };
    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }

  static Map<String, Object?> _lessonJson(CourseLesson lesson, ProgressStore progress) {
    final first = lesson.translations.values.first;
    final finished = progress.finishedIn(lesson);
    return {
      'id': lessonIdOf(lesson),
      'group': ?lesson.entry.group?.id,
      'optional': first.optional,
      'steps': [
        for (final section in first.sections)
          {
            'id': section.id,
            'type': section.kind.type,
            'optional': section.optional,
            'done': finished.contains(section.id),
          },
      ],
    };
  }

  /// The finished steps that [course] still has, by its own lessons.
  ProgressImport matchTo(Course course) {
    final lessons = {for (final lesson in course.lessons) lessonIdOf(lesson): lesson};
    final matched = <CourseLesson, Set<String>>{};
    var skipped = 0;

    for (final MapEntry(key: id, value: steps) in finished.entries) {
      final lesson = lessons[id];
      final known = {...?lesson?.translations.values.first.sections.map((section) => section.id)};
      final placed = steps.intersection(known);
      skipped += steps.length - placed.length;
      if (placed.isNotEmpty) matched[lesson!] = placed;
    }

    return ProgressImport(matched, skipped: skipped);
  }

}

/// Why a file could not be read as a [ProgressFile].
enum ProgressFileProblem {

  /// Not JSON, or JSON that does not say it is a progress file.
  notProgress,

  /// Written by a newer version of the app than this one.
  newer,

  /// Says it is a progress file, but something in it does not hold.
  damaged,

}

class ProgressFileException implements Exception {

  final ProgressFileProblem problem;

  const ProgressFileException(this.problem);

  @override
  String toString() => 'ProgressFileException: ${problem.name}';

}

/// A [ProgressFile] held against the course this app has.
class ProgressImport {

  /// The finished sections, by lesson. Holds only lessons and sections the
  /// course has, and no lesson without one.
  final Map<CourseLesson, Set<String>> finished;

  /// How many finished steps name a lesson or a section the course does not
  /// have.
  final int skipped;

  const ProgressImport(this.finished, {required this.skipped});

  /// How many finished steps there are to record.
  int get steps => finished.values.fold(0, (sum, sections) => sum + sections.length);

}
