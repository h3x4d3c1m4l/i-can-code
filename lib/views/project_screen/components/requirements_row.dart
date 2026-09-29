import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/project_screen/project_screen_controller.dart';

/// The lessons a task leans on, each marked with how far the student is.
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
          context.localizations.projectScreen_requires,
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
        l10n.projectScreen_requirementFinished(requirement.title),
      ),
      RequirementStatus.started => (
        FLucideIcons.circleDashed,
        theme.primary,
        l10n.projectScreen_requirementStarted(requirement.title),
      ),
      RequirementStatus.notStarted => (
        FLucideIcons.circle,
        theme.mutedForeground,
        l10n.projectScreen_requirementNotStarted(requirement.title),
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
