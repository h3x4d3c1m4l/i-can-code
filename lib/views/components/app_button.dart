import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// What a button means, which decides how it is filled.
enum AppButtonTone {

  /// The step's main action: Run, Verder, Volgende. The brand fill.
  primary,

  /// The quieter one beside it — "Terug naar overzicht". Foreground-filled.
  neutral,
}

/// The app's button.
///
/// Not forui's [FButton]: its padding is `10 × 11` against the design's
/// `38 × 19`, and it fills with a [BoxDecoration], which cannot draw a squircle.
/// Still built on [FTappable], so hover, focus, keyboard activation and button
/// semantics come from the framework.
class AppButton extends StatelessWidget {

  final Widget child;

  /// Null disables the button, which dims it and stops it responding.
  final VoidCallback? onPress;

  final AppButtonTone tone;

  /// Swaps the label for a spinner **without resizing the button**: the label
  /// stays laid out and merely turns invisible.
  final bool busy;

  const AppButton({
    required this.child,
    required this.onPress,
    this.tone = AppButtonTone.primary,
    this.busy = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final enabled = onPress != null;

    final (background, foreground) = switch (tone) {
      AppButtonTone.primary => (theme.colors.primary, theme.colors.primaryForeground),
      AppButtonTone.neutral => (theme.colors.foreground, theme.colors.background),
    };

    return FTappable(
      onPress: onPress,
      semanticsButton: true,
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          color: switch (states) {
            _ when states.contains(FTappableVariant.disabled) => background.withValues(alpha: 0.4),
            _ when states.contains(FTappableVariant.pressed) => background.withValues(alpha: 0.75),
            _ when states.contains(FTappableVariant.hovered) => background.withValues(alpha: 0.86),
            _ => background,
          },
          shape: squircle(kControlCornerRadius),
        ),
        child: Padding(
          // The design's own measurements: 38 across, 19 down.
          padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 19),
          child: child,
        ),
      ),
      child: DefaultTextStyle(
        style: context.appTheme.text.label.copyWith(
          fontSize: 18,
          letterSpacing: 0,
          color: foreground.withValues(alpha: enabled ? 1 : 0.6),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Still laid out, so it keeps holding the button's width open.
            Visibility.maintain(visible: !busy, child: child),
            // Positioned, so the spinner cannot contribute to the Stack's
            // size — a taller spinner than label would otherwise grow it.
            if (busy)
              Positioned.fill(
                child: Center(
                  child: FCircularProgress(
                    style: FCircularProgressStyleDelta.delta(
                      iconStyle: IconThemeDataDelta.delta(color: foreground, size: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
