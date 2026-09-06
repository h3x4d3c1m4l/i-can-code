import 'package:yaml/yaml.dart';

/// What a section asks of the student.
enum SectionKind {

  /// Prose only. Nothing to write, nothing to run.
  info,

  /// A short exercise. Prose and editor stack in a single column.
  quickExercise,

  /// A full exercise, in the design's two-column layout: prose on the left,
  /// editor and output on the right.
  exercise,

  /// Match the pairs: prose, then a board of tiles the student pairs up. Asks
  /// for work but not for code, so there is no editor and nothing to run — the
  /// board itself is the check.
  matchPairs,

  /// Predict the output: the lesson's own program, and a box to write what the
  /// student thinks it prints before it is run.
  ///
  /// Code runs here, but the student writes none of it, so this is not an
  /// assignment: there is no editor and no validator. **The answer key is the
  /// interpreter** — the program is run and its output compared to the
  /// prediction — so a lesson cannot state one that drifts from the code beside
  /// it.
  predictOutput,

  /// Put the lines in order: the program's own lines, shuffled, for the student
  /// to arrange into a working one.
  ///
  /// The rung between reading a worked example and writing code from nothing —
  /// the syntax is given, so what is being practised is the shape of the
  /// program. Checked by **running what was assembled** through the section's
  /// ordinary validator, never by comparing it against the order in the file,
  /// so an arrangement that is different but correct still passes.
  orderLines;

  /// Whether the student writes and runs code here.
  ///
  /// Stated as the two kinds it is true of rather than as "not [info]":
  /// [matchPairs] is not prose either, and reading it as an assignment would
  /// have the parser demand an editor for a step that has none.
  bool get isAssignment => this == SectionKind.quickExercise || this == SectionKind.exercise;

  /// Whether the step carries hidden checks.
  ///
  /// Wider than [isAssignment] by exactly one: [orderLines] runs a program and
  /// is checked like an exercise, but the student assembles it rather than
  /// typing it, so it has no editor and no starter block.
  bool get usesValidator => isAssignment || this == SectionKind.orderLines;

  static SectionKind parse(String value) => switch (value) {
    'info' => SectionKind.info,
    'quick-exercise' => SectionKind.quickExercise,
    'exercise' => SectionKind.exercise,
    'match-pairs' => SectionKind.matchPairs,
    'predict-output' => SectionKind.predictOutput,
    'order-lines' => SectionKind.orderLines,
    _ => throw FormatException('Unknown section type "$value".'),
  };

}

/// One tile of a [SectionKind.matchPairs] board: which pair it belongs to, and
/// which of that pair's two halves it is.
///
/// A board holds two of these per [LessonPair] and deals them into one pool, so
/// picking two tiles of the same [pair] is what makes a match. A record, for the
/// value equality — a tile has to be findable in a set of picks.
typedef PairHalf = ({int pair, bool cue});

/// Two halves of one item on a [SectionKind.matchPairs] board.
///
/// The board deals both into **one pool**, so which of the two is written first
/// changes nothing the student sees. The names say how a pair is written rather
/// than how it is drawn: the thing, and then what is said about it.
///
/// Both are inline markdown, rendered the way a section's prose is, so a tile
/// may name a function in `code` spans.
class LessonPair {

  /// The half written first — what the pair is about.
  final String cue;

  /// The half written second. Not "the right one": either half is found by
  /// picking the other.
  final String answer;

  const LessonPair({required this.cue, required this.answer});

}

/// One step of a lesson — one `##` section of the markdown file.
class LessonSection {

  /// Stable across edits, unlike the section's position. Saved progress keys on
  /// this so a tick survives the author reordering a lesson.
  final String id;

  final String title;
  final SectionKind kind;

  /// The step's own emoji, from the section's `metadata`. Shown beside the
  /// title and nowhere else — a breadcrumb stays text.
  ///
  /// Nullable so a lesson missing one still opens; `test/services/lesson_test.dart`
  /// is what holds every lesson that ships to having one.
  final String? emoji;

  /// A "Verdieping": worth reading, but not required. The step carries a badge
  /// and a way past it, and skipping it stores nothing — see
  /// `docs/lesson-format.md`.
  final bool optional;

  /// The section's prose, as markdown source, with every block that has a role
  /// of its own removed — `metadata`, `<lang>-assignment`, `<lang>-validator`,
  /// `<lang>-predict`, `pairs` and `explanation`. Plain fenced blocks stay in:
  /// those are worked examples the student reads.
  final String prose;

  /// What the editor opens with. Empty for a blank start; null on an [info]
  /// section, which has no editor.
  final String? starter;

  /// The hidden checks. See `docs/lesson-format.md` for the contract.
  final String? validator;

  /// What the student matches up, from the section's `pairs` block. Empty on
  /// every kind but [SectionKind.matchPairs], which the parser holds to at
  /// least two.
  final List<LessonPair> pairs;

  /// The program whose output the student predicts, from the section's
  /// `<lang>-predict` block. Null on every kind but
  /// [SectionKind.predictOutput], which the parser holds to a non-empty one.
  ///
  /// Read, never edited: it is the question, and running it is what answers it.
  final String? program;

  /// Why the output is what it is, from the section's `explanation` block, shown
  /// **after** the answer. Inline markdown, rendered the way prose is. Null when
  /// the author wrote none, which is allowed.
  ///
  /// Optional on [SectionKind.predictOutput] and refused everywhere else: it is
  /// the feedback half of a prediction, and feedback is what turns a wrong guess
  /// from a dead end into the point of the step.
  final String? explanation;

  /// The lines a [SectionKind.orderLines] step is assembled from, **in the
  /// order the author wrote them** — which is the one order the board never
  /// deals. Empty on every other kind.
  ///
  /// Each keeps its own leading whitespace: the indentation belongs to the line
  /// and travels with it, so the student arranges a program rather than also
  /// having to indent it.
  final List<String> lines;

  /// Lines that belong to no correct program — they are on the board to be left
  /// there. Optional, and empty on every kind but [SectionKind.orderLines].
  ///
  /// They need nothing of the board: a distractor that is used makes the
  /// assembled program wrong, and the validator says so the way it would about
  /// any other mistake.
  final List<String> distractors;

  const LessonSection({
    required this.id,
    required this.title,
    required this.kind,
    required this.prose,
    this.emoji,
    this.optional = false,
    this.starter,
    this.validator,
    this.pairs = const [],
    this.program,
    this.explanation,
    this.lines = const [],
    this.distractors = const [],
  });

}

/// One lesson: a single markdown file, in one locale. Metadata, prose, starter
/// code and hidden validators all live in that file. See
/// `docs/lesson-format.md`.
class Lesson {

  /// From the document-level `metadata` block. Shared by every locale.
  final String id;

  /// The `#` heading.
  final String title;

  /// The paragraph under the heading, before the first `metadata` block. Null
  /// when the lesson does not have one.
  final String? subtitle;

  /// The lesson's own emoji, from the document-level `metadata`. It fills the
  /// tile on its catalog card, in place of the order number.
  ///
  /// Nullable for the same reason [LessonSection.emoji] is: a lesson missing one
  /// still opens, and the card falls back to the number.
  final String? emoji;

  final List<LessonSection> sections;

  const Lesson({
    required this.id,
    required this.title,
    this.subtitle,
    this.emoji,
    required this.sections,
  });

  /// How many steps the student walks through.
  int get stepCount => sections.length;

  /// Parses [source], one lesson file.
  ///
  /// Line-based rather than through the `markdown` package: the prose has to
  /// come back out as **source** for `flutter_markdown_plus`, which takes a
  /// string and offers no way to hand it a tree.
  ///
  /// Throws a [FormatException] naming what is wrong rather than returning a
  /// half-built lesson.
  factory Lesson.parse(String source) {
    String? id;
    String? title;
    String? subtitle;
    String? emoji;
    final sections = <LessonSection>[];

    String? sectionTitle;
    String? sectionId;
    String? sectionEmoji;
    SectionKind? sectionKind;
    var sectionOptional = false;
    var prose = <String>[];
    String? starter;
    String? validator;
    // Nullable, unlike `LessonSection.pairs`: "no `pairs` block" and "a `pairs`
    // block with nothing in it" are different mistakes.
    List<LessonPair>? pairs;
    String? program;
    String? explanation;
    List<String>? ordered;
    List<String>? distractors;

    void flush() {
      if (sectionTitle == null) return;
      if (sectionKind == null) {
        throw FormatException('Section "$sectionTitle" has no `metadata` block declaring its type.');
      }
      if (sectionId == null) {
        throw FormatException('Section "$sectionTitle" declares no `id`. Saved progress keys on it.');
      }
      if (sectionKind!.isAssignment && starter == null) {
        throw FormatException('Section "$sectionTitle" is a ${sectionKind!.name} but has no assignment block.');
      }
      if (!sectionKind!.isAssignment && starter != null) {
        throw FormatException('Section "$sectionTitle" is a ${sectionKind!.name} step but carries an assignment block.');
      }
      // Wider than the editor: an order-lines step runs a program and is
      // checked like an exercise, but has nothing to type in.
      if (sectionKind!.usesValidator && validator == null) {
        throw FormatException('Section "$sectionTitle" is a ${sectionKind!.name} but has no validator block.');
      }
      if (!sectionKind!.usesValidator && validator != null) {
        throw FormatException('Section "$sectionTitle" is a ${sectionKind!.name} step but carries a validator block.');
      }
      if (sectionKind == SectionKind.matchPairs) {
        if (pairs == null) {
          throw FormatException('Section "$sectionTitle" is a match-pairs step but has no `pairs` block.');
        }
        // One pair is not a game: its two tiles are the only two on the board.
        if (pairs!.length < 2) {
          throw FormatException('Section "$sectionTitle" declares ${pairs!.length} pair(s); a board needs at least 2.');
        }
      } else if (pairs != null) {
        throw FormatException('Section "$sectionTitle" is a ${sectionKind!.name} step but carries a `pairs` block.');
      }
      if (sectionKind == SectionKind.predictOutput) {
        if (program == null) {
          throw FormatException('Section "$sectionTitle" is a predict-output step but has no predict block.');
        }
        // A program that prints nothing has no output to predict, and the step
        // would pass on an empty answer.
        if (program!.trim().isEmpty) {
          throw FormatException('Section "$sectionTitle" declares an empty predict block; there is nothing to run.');
        }
      } else if (program != null) {
        throw FormatException('Section "$sectionTitle" is a ${sectionKind!.name} step but carries a predict block.');
      }
      if (sectionKind == SectionKind.orderLines) {
        if (ordered == null) {
          throw FormatException('Section "$sectionTitle" is an order-lines step but has no order block.');
        }
        // One line is already in order, so there is nothing to arrange.
        if (ordered!.length < 2) {
          throw FormatException(
            'Section "$sectionTitle" has ${ordered!.length} line(s) to order; arranging needs at least 2.',
          );
        }
      } else if (ordered != null || distractors != null) {
        throw FormatException(
          'Section "$sectionTitle" is a ${sectionKind!.name} step but carries an order or distractors block.',
        );
      }
      // Optional where it belongs, refused everywhere else: it is shown with the
      // answer to a prediction, and no other kind has an answer to show it with.
      if (sectionKind != SectionKind.predictOutput && explanation != null) {
        throw FormatException(
          'Section "$sectionTitle" is a ${sectionKind!.name} step but carries an `explanation` block.',
        );
      }
      sections.add(
        LessonSection(
          id: sectionId!,
          title: sectionTitle,
          kind: sectionKind!,
          emoji: sectionEmoji,
          optional: sectionOptional,
          prose: prose.join('\n').trim(),
          starter: starter,
          validator: validator,
          pairs: pairs ?? const [],
          program: program,
          explanation: explanation,
          lines: ordered ?? const [],
          distractors: distractors ?? const [],
        ),
      );
      sectionKind = null;
      sectionId = null;
      sectionEmoji = null;
      sectionOptional = false;
      prose = <String>[];
      starter = null;
      validator = null;
      pairs = null;
      program = null;
      explanation = null;
      ordered = null;
      distractors = null;
    }

    final lines = source.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final fence = _Fence.opening(line);

      if (fence != null) {
        final body = <String>[];
        var closed = false;
        for (i++; i < lines.length; i++) {
          if (fence.closes(lines[i])) {
            closed = true;
            break;
          }
          body.add(lines[i]);
        }
        if (!closed) throw FormatException('Unclosed ``` block starting at line ${i + 1}.');

        switch (fence.role) {
          case _BlockRole.metadata:
            final meta = loadYaml(body.join('\n'));
            if (meta is! YamlMap) throw const FormatException('A `metadata` block is not a YAML mapping.');
            if (sectionTitle == null) {
              id = meta['id'] as String? ?? id;
              emoji = _readEmoji(meta, 'The lesson') ?? emoji;
            } else {
              final type = meta['type'] as String?;
              if (type == null) throw FormatException('Section "$sectionTitle" declares no `type`.');
              sectionKind = SectionKind.parse(type);
              sectionId = meta['id'] as String?;
              final emoji = meta['emoji'];
              if (emoji != null && emoji is! String) {
                throw FormatException('Section "$sectionTitle" declares an `emoji` that is not text.');
              }
              sectionEmoji = (emoji as String?)?.trim();
              if (sectionEmoji != null && sectionEmoji!.isEmpty) {
                throw FormatException('Section "$sectionTitle" declares an empty `emoji`.');
              }
              final optional = meta['optional'];
              if (optional != null && optional is! bool) {
                throw FormatException('Section "$sectionTitle" declares an `optional` that is not true or false.');
              }
              sectionOptional = optional as bool? ?? false;
            }
          case _BlockRole.assignment:
            starter = body.join('\n');
          case _BlockRole.validator:
            validator = body.join('\n');
          case _BlockRole.predict:
            program = body.join('\n');
          case _BlockRole.order:
            ordered = _codeLines(body);
          case _BlockRole.distractors:
            distractors = _codeLines(body);
          case _BlockRole.explanation:
            if (sectionTitle == null) {
              throw const FormatException('An `explanation` block belongs to a section, not to the lesson.');
            }
            final text = body.join('\n').trim();
            if (text.isEmpty) {
              throw FormatException('Section "$sectionTitle" declares an empty `explanation` block.');
            }
            explanation = text;
          case _BlockRole.pairs:
            if (sectionTitle == null) {
              throw const FormatException('A `pairs` block belongs to a section, not to the lesson.');
            }
            pairs = _parsePairs(body, sectionTitle);
          case _BlockRole.sample:
            // A worked example. Put the fence back so the renderer still sees
            // a code block.
            prose
              ..add(line)
              ..addAll(body)
              ..add(fence.marker);
        }
        continue;
      }

      if (line.startsWith('# ') && title == null) {
        title = line.substring(2).trim();
        continue;
      }
      if (line.startsWith('## ')) {
        flush();
        sectionTitle = line.substring(3).trim();
        continue;
      }

      if (sectionTitle == null) {
        // Between the title and the first section: the lesson's subtitle.
        if (title != null && subtitle == null && line.trim().isNotEmpty) subtitle = line.trim();
      } else {
        prose.add(line);
      }
    }
    flush();

    if (id == null) throw const FormatException('The lesson has no document-level `metadata` block with an `id`.');
    if (title == null) throw const FormatException('The lesson has no `#` title.');
    if (sections.isEmpty) throw const FormatException('The lesson has no `##` sections.');

    return Lesson(id: id, title: title, subtitle: subtitle, emoji: emoji, sections: sections);
  }

  /// Reads a `pairs` block: one pair per paragraph, two lines each.
  ///
  /// Line-based rather than YAML because a tile is arbitrary text — `print("a:
  /// b")` is a plain scalar YAML would refuse — and because a separator
  /// character would sooner or later appear inside a tile. A blank line is the
  /// one thing that cannot.
  static List<LessonPair> _parsePairs(List<String> body, String section) {
    final pairs = <LessonPair>[];
    var block = <String>[];

    void flush() {
      if (block.isEmpty) return;
      if (block.length != 2) {
        throw FormatException(
          'Section "$section" has a pair of ${block.length} lines; a pair is two, separated from the next by a '
          'blank line.',
        );
      }
      pairs.add(LessonPair(cue: block[0].trim(), answer: block[1].trim()));
      block = <String>[];
    }

    for (final line in body) {
      if (line.trim().isEmpty) {
        flush();
        continue;
      }
      block.add(line);
    }
    flush();

    return pairs;
  }

  /// One tile per line of an order or distractors block.
  ///
  /// Blank lines are dropped — a blank line is a gap in the source, not a tile —
  /// and trailing whitespace with them. **Leading whitespace is kept**: the
  /// indentation belongs to the line and travels with it, so a student arranges
  /// a program rather than also having to indent it.
  static List<String> _codeLines(List<String> body) =>
      body.map((line) => line.trimRight()).where((line) => line.isNotEmpty).toList();

  static String? _readEmoji(YamlMap meta, String owner) {
    final emoji = meta['emoji'];
    if (emoji == null) return null;
    if (emoji is! String) throw FormatException('$owner declares an `emoji` that is not text.');

    final trimmed = emoji.trim();
    if (trimmed.isEmpty) throw FormatException('$owner declares an empty `emoji`.');
    return trimmed;
  }

}

enum _BlockRole { metadata, assignment, validator, predict, order, distractors, explanation, pairs, sample }

/// An opening code fence, with its role read off the language it declares:
/// ```` ```python-assignment ````. Stripping the `-assignment` / `-validator`
/// suffix leaves the plain language for a syntax highlighter.
class _Fence {

  static final RegExp _pattern = RegExp(r'^(\s*)(`{3,}|~{3,})\s*([^\s`]*)');

  final String marker;
  final _BlockRole role;

  /// The programming language, with any role suffix removed.
  final String? language;

  const _Fence({required this.marker, required this.role, required this.language});

  /// Reads [line] as an opening fence, or returns null if it is not one.
  static _Fence? opening(String line) {
    final match = _pattern.firstMatch(line);
    if (match == null) return null;

    final marker = match.group(2)!;
    final declared = match.group(3)!;

    if (declared == 'metadata') {
      return _Fence(marker: marker, role: _BlockRole.metadata, language: null);
    }
    // Reserved the way `metadata` is, and for the same reason: what a
    // match-pairs board holds is not a programming language.
    if (declared == 'pairs') {
      return _Fence(marker: marker, role: _BlockRole.pairs, language: null);
    }
    // Reserved for the same reason again — it is prose about the code, not code.
    if (declared == 'explanation') {
      return _Fence(marker: marker, role: _BlockRole.explanation, language: null);
    }
    for (final (suffix, role) in const [
      ('-assignment', _BlockRole.assignment),
      ('-validator', _BlockRole.validator),
      ('-predict', _BlockRole.predict),
      ('-order', _BlockRole.order),
      ('-distractors', _BlockRole.distractors),
    ]) {
      if (declared.endsWith(suffix)) {
        return _Fence(
          marker: marker,
          role: role,
          language: declared.substring(0, declared.length - suffix.length),
        );
      }
    }
    return _Fence(marker: marker, role: _BlockRole.sample, language: declared.isEmpty ? null : declared);
  }

  /// A closing fence is the same character, at least as long, and carries no
  /// info string — the CommonMark rule.
  bool closes(String line) {
    final trimmed = line.trim();
    return trimmed.startsWith(marker[0]) &&
        trimmed.length >= marker.length &&
        trimmed.split('').every((char) => char == marker[0]);
  }

}
