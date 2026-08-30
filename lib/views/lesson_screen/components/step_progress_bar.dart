import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The lesson's progress, sized to sit in the header beside the settings cog.
///
/// One fixed-width segment per step rather than a full-width bar, which would
/// push the cog around as the lesson's length changed. Segments are tappable.
class StepProgressBar extends StatelessWidget {

  /// How wide one step is drawn.
  static const double segmentWidth = 32;

  final int stepCount;
  final int current;
  final Set<int> passed;
  final ValueChanged<int> onTap;

  const StepProgressBar({
    required this.stepCount,
    required this.current,
    required this.passed,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var step = 0; step < stepCount; step++) ...[
          if (step > 0) const SizedBox(width: 6),
          FTappable(
            // Keyed so a test can address one segment: `FTappable` resolves to
            // a private widget and cannot be found by type.
            key: ValueKey(step),
            semanticsButton: true,
            semanticsLabel: '${step + 1} / $stepCount',
            onPress: () => onTap(step),
            builder: (context, states, _) => SizedBox(
              // The bar is 6px tall, too thin to click, so the gesture area is
              // padded out around it.
              width: segmentWidth,
              height: 28,
              child: Center(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: switch (step) {
                      _ when passed.contains(step) => colors.progressComplete,
                      _ when step == current => colors.progressCurrent,
                      _ when states.contains(FTappableVariant.hovered) => colors.progressCurrent.withValues(alpha: 0.4),
                      _ => colors.progressTrack,
                    },
                    shape: squircleOf(kProgressCornerRadius, size: 6),
                  ),
                  child: const SizedBox(height: 6, width: segmentWidth),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

}
