import 'package:yaml/yaml.dart';

/// What a section asks of the student.
enum SectionKind {

  /// Prose only. Nothing to write, nothing to run.
  info,

  /// A short assignment. Prose and editor stack in a single column.
  shortAssignment,

  /// A full assignment, in the design's two-column layout: prose on the left,
  /// editor and output on the right.
  longAssignment;

  /// Whether the student writes and runs code here.
  bool get isAssignment => this != SectionKind.info;

  static SectionKind parse(String value) => switch (value) {
    'info' => SectionKind.info,
    'short-assignment' => SectionKind.shortAssignment,
    'long-assignment' => SectionKind.longAssignment,
    _ => throw FormatException('Unknown section type "$value".'),
  };

}

/// One step of a lesson — one `##` section of the markdown file.
class LessonSection {

  /// Stable across edits, unlike the section's position. Saved progress keys on
  /// this so a tick survives the author reordering a lesson.
  final String id;

  final String title;
  final SectionKind kind;

  /// The section's prose, as markdown source, with the `metadata`,
  /// `<lang>-assignment` and `<lang>-validator` blocks removed. Plain fenced
  /// blocks stay in — those are worked examples the student reads.
  final String prose;

  /// What the editor opens with. Empty for a blank start; null on an [info]
  /// section, which has no editor.
  final String? starter;

  /// The hidden checks. See `docs/lesson-format.md` for the contract.
  final String? validator;

  const LessonSection({
    required this.id,
    required this.title,
    required this.kind,
    required this.prose,
    this.starter,
    this.validator,
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

  final List<LessonSection> sections;

  const Lesson({
    required this.id,
    required this.title,
    this.subtitle,
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
    final sections = <LessonSection>[];

    String? sectionTitle;
    String? sectionId;
    SectionKind? sectionKind;
    var prose = <String>[];
    String? starter;
    String? validator;

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
      if (!sectionKind!.isAssignment && (starter != null || validator != null)) {
        throw FormatException('Section "$sectionTitle" is info but carries an assignment or validator block.');
      }
      sections.add(
        LessonSection(
          id: sectionId!,
          title: sectionTitle,
          kind: sectionKind!,
          prose: prose.join('\n').trim(),
          starter: starter,
          validator: validator,
        ),
      );
      sectionKind = null;
      sectionId = null;
      prose = <String>[];
      starter = null;
      validator = null;
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
            } else {
              final type = meta['type'] as String?;
              if (type == null) throw FormatException('Section "$sectionTitle" declares no `type`.');
              sectionKind = SectionKind.parse(type);
              sectionId = meta['id'] as String?;
            }
          case _BlockRole.assignment:
            starter = body.join('\n');
          case _BlockRole.validator:
            validator = body.join('\n');
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

    return Lesson(id: id, title: title, subtitle: subtitle, sections: sections);
  }

}

enum _BlockRole { metadata, assignment, validator, sample }

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
    for (final (suffix, role) in const [('-assignment', _BlockRole.assignment), ('-validator', _BlockRole.validator)]) {
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
