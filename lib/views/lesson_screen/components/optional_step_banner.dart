import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The eyebrow over an optional step — a "Verdieping": what it is, and the way
/// past it.
///
/// The badge is filled rather than outlined so it reads as a label on the step
/// and not as a control; the way past it is a link beside it, because skipping
/// is the quiet choice and a second button would compete with "Volgende".
class OptionalStepBanner extends StatelessWidget {

  /// Leaves the step without completing it.
  final VoidCallback onSkip;

  const OptionalStepBanner({required this.onSkip, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            color: theme.colors.secondary,
            shape: squircle(kChipCornerRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Text(
              context.localizations.lessonScreen_optional.toUpperCase(),
              style: tokens.text.label.copyWith(fontSize: 12, color: theme.colors.secondaryForeground),
            ),
          ),
        ),
        const SizedBox(width: 16),
        FTappable(
          semanticsButton: true,
          onPress: onSkip,
          builder: (context, states, child) => Opacity(
            opacity: states.contains(FTappableVariant.hovered) ? 0.75 : 1,
            child: child,
          ),
          child: Text(
            context.localizations.lessonScreen_skip,
            style: tokens.text.bodySmall.copyWith(
              fontSize: 16,
              height: 1,
              color: tokens.colors.link,
              // Underlined as well as coloured: `link` is the only role that
              // clears AA as text, and the underline is what makes it a link
              // in a preset whose colours are close together.
              decoration: TextDecoration.underline,
              decorationColor: tokens.colors.link,
            ),
          ),
        ),
      ],
    );
  }

}
