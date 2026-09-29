import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The lesson's progress, sized to sit in the header beside the settings cog.
///
/// One fixed-width segment per step rather than a full-width bar, which would
/// push the cog around as the lesson's length changed. Segments are tappable,
/// and each names its own step on hover.
class StepProgressBar extends StatelessWidget {

  /// How wide one step is drawn.
  static const double segmentWidth = 32;

  /// One per step, in order. What a segment says when it is hovered, and what a
  /// screen reader reads in place of a bare position: a row of identical bars is
  /// otherwise the one part of the header that cannot say where it goes.
  final List<String> titles;

  final int current;
  final Set<int> passed;
  final ValueChanged<int> onTap;

  const StepProgressBar({
    required this.titles,
    required this.current,
    required this.passed,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;

    final stepCount = titles.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var step = 0; step < stepCount; step++) ...[
          if (step > 0) const SizedBox(width: 6),
          // An FTooltip and not the popover the catalog's hint uses: this one is
          // wanted on hover and must *not* survive the press, which is a move to
          // another step. forui's tooltip hides on pointer down, which is the
          // behaviour this needs and the reason the hint could not use it.
          FTooltip(
            // No dwell time: forui waits out half a second, and on a 32px bar
            // that reads as the hover doing nothing at all.
            style: FTooltipStyleDelta.delta(hoverEnterDuration: Duration.zero),
            tipBuilder: (context, _) => Text('${step + 1}. ${titles[step]}'),
            child: FTappable(
              // Keyed so a test can address one segment: `FTappable` resolves to
              // a private widget and cannot be found by type.
              key: ValueKey(step),
              semanticsButton: true,
              semanticsLabel: '${step + 1} / $stepCount: ${titles[step]}',
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
                        _ when states.contains(FTappableVariant.hovered) =>
                          colors.progressCurrent.withValues(alpha: 0.4),
                        _ => colors.progressTrack,
                      },
                      shape: squircleOf(kProgressCornerRadius, size: 6),
                    ),
                    child: const SizedBox(height: 6, width: segmentWidth),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

}
