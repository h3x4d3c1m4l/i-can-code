import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// How far a student is with a lesson that is recommended first.
enum RequirementStatus { finished, started, notStarted }

/// One lesson that is recommended first, ready to be drawn.
typedef Requirement = ({String title, RequirementStatus status, CourseLesson lesson});

/// The lessons [ids] name in [subject], in [locale], each with how far the
/// student is. An id the course does not have is left out: the content test is
/// what catches it, and a student can do nothing about it.
List<Requirement> requirementsFor(
  Iterable<String> ids, {
  required String subject,
  required String locale,
  required Course course,
  required ProgressStore progress,
}) => [
  for (final id in ids)
    if (course.lessonsFor(subject).where((l) => l.translations.values.first.id == id).firstOrNull
        case final CourseLesson lesson)
      (
        title: lesson.forLocale(locale).title,
        status: progress.isFinished(lesson)
            ? RequirementStatus.finished
            : progress.isStarted(lesson)
            ? RequirementStatus.started
            : RequirementStatus.notStarted,
        lesson: lesson,
      ),
];

/// The lessons a project task or a whole lesson leans on, each marked with how
/// far the student is.
///
/// Advice and never a gate, so it is set small and muted: a student who has
/// not done a lesson reads that it would help, not that they are locked out.
class RequirementsRow extends StatelessWidget {

  final List<Requirement> requirements;

  /// Opens a lesson from the row.
  final ValueChanged<CourseLesson> onOpen;

  const RequirementsRow({required this.requirements, required this.onOpen, super.key});

  @override
  Widget build(BuildContext context) {
    final muted = context.theme.colors.mutedForeground;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          context.localizations.requirementsRow_title,
          style: context.appTheme.text.bodySmall.copyWith(color: muted),
        ),
        for (final requirement in requirements) _Chip(requirement: requirement, onOpen: onOpen),
      ],
    );
  }

}

class _Chip extends StatelessWidget {

  final Requirement requirement;
  final ValueChanged<CourseLesson> onOpen;

  const _Chip({required this.requirement, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final l10n = context.localizations;
    final colors = context.appTheme.colors;
    final theme = context.theme.colors;

    // A mark and not only a colour, so the three states read without it.
    final (icon, color, label) = switch (requirement.status) {
      RequirementStatus.finished => (
        FLucideIcons.circleCheck,
        colors.success,
        l10n.requirementsRow_finished(requirement.title),
      ),
      RequirementStatus.started => (
        FLucideIcons.circleDashed,
        theme.primary,
        l10n.requirementsRow_started(requirement.title),
      ),
      RequirementStatus.notStarted => (
        FLucideIcons.circle,
        theme.mutedForeground,
        l10n.requirementsRow_notStarted(requirement.title),
      ),
    };

    return FTappable(
      semanticsButton: true,
      semanticsLabel: label,
      onPress: () => onOpen(requirement.lesson),
      builder: (context, states, _) => DecoratedBox(
        decoration: ShapeDecoration(
          color: states.contains(FTappableVariant.hovered) ? theme.secondary : null,
          shape: squircle(kChipCornerRadius, side: BorderSide(color: theme.border, width: 1.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              ExcludeSemantics(
                child: Text(requirement.title, style: context.appTheme.text.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
