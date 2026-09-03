import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_button_row.dart';

/// The page a lesson ends on: what was just finished, and the two ways out of
/// it.
///
/// It is a page rather than a dialog because it is where the course carries on
/// from — a dialog over the last step would put the way to the next lesson on
/// top of work that is already done.
///
/// It is not a step either. It carries no id, counts towards no `stepCount` and
/// keeps no progress, so a lesson file says nothing about it and the progress
/// bar draws nothing for it.
class LessonCompletePanel extends StatelessWidget {

  /// The lesson's own emoji, drawn in the tile. Null falls back to a tick, for
  /// a lesson whose file declares none.
  final String? emoji;

  final String title;

  /// How many of the lesson's steps were actually finished. Short of
  /// [stepCount] when a "Verdieping" was skipped, which is what makes the
  /// headline say "einde van" rather than "afgerond".
  final int completedSteps;

  final int stepCount;

  /// Opens the lesson after this one. Null when this was the last one in the
  /// language, which leaves [onLeave] as the only way on.
  final VoidCallback? onNextLesson;

  /// Back to the lesson's last step. The end page is past the last step rather
  /// than instead of it, so there is always somewhere behind it.
  final VoidCallback onBack;

  /// What [onBack] is announced as, since it is a glyph with no label.
  final String backLabel;

  /// Back to the catalog. Always offered.
  final VoidCallback onLeave;

  /// What [onLeave] is called — "Terug naar Python", named for where it lands.
  final String leaveLabel;

  const LessonCompletePanel({
    required this.title,
    required this.completedSteps,
    required this.stepCount,
    required this.onLeave,
    required this.leaveLabel,
    required this.onBack,
    required this.backLabel,
    this.emoji,
    this.onNextLesson,
    super.key,
  });

  bool get _finished => completedSteps >= stepCount;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final text = context.appTheme.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildTile(context),
        const SizedBox(height: 34),
        Text(
          _finished
              ? context.localizations.lessonScreen_completeTitle(title)
              : context.localizations.lessonScreen_completePartialTitle(title),
          style: text.h1.copyWith(fontSize: 38),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          context.localizations.lessonScreen_completeSteps(completedSteps, stepCount),
          style: text.body.copyWith(fontSize: 19, color: theme.colors.mutedForeground),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        // Wrapped, so the buttons stack instead of overflowing on a phone. The
        // back button travels with the one it belongs beside, in a row of their
        // own, rather than wrapping away from it.
        Wrap(
          spacing: AppButtonRow.gap,
          runSpacing: AppButtonRow.gap,
          alignment: WrapAlignment.center,
          children: [
            AppButtonRow(
              children: [
                AppButton.icon(
                  icon: FLucideIcons.chevronLeft,
                  semanticsLabel: backLabel,
                  onPress: onBack,
                ),
                if (onNextLesson case final VoidCallback next)
                  AppButton(
                    icon: FLucideIcons.chevronRight,
                    iconSide: AppButtonIconSide.trailing,
                    onPress: next,
                    child: Text(context.localizations.lessonScreen_nextLesson),
                  ),
              ],
            ),
            AppButton(
              // The brand fill is the way forward, so it goes to the next
              // lesson when there is one and to the catalog when there is not.
              tone: onNextLesson == null ? AppButtonTone.primary : AppButtonTone.neutral,
              // The lessons it goes back to are a list, not a grid.
              icon: FLucideIcons.list,
              onPress: onLeave,
              child: Text(leaveLabel),
            ),
          ],
        ),
      ],
    );
  }

  /// The lesson's tile, the same one its catalog card carries, at the size an
  /// end page can give it.
  Widget _buildTile(BuildContext context) {
    const double size = 108;
    final theme = context.theme;

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.primary,
          shape: squircleOf(kCardCornerRadius, size: size),
        ),
        child: Center(
          child: emoji != null
              ? Text(
                  emoji!,
                  style: const TextStyle(fontFamilyFallback: kEmojiFontFallback, fontSize: 56, height: 1),
                )
              : Icon(FLucideIcons.check, size: 56, color: theme.colors.primaryForeground),
        ),
      ),
    );
  }

}
