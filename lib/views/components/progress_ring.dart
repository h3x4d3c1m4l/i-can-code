import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';

/// A ring that fills as [value] goes from 0 to 1, or forui's spinner when there
/// is no value to show.
///
/// forui has a spinner and a determinate *bar*, and no ring that carries a
/// value. This is the ring the splash in `web/index.html` draws, continued in
/// the app. Both states take the same box, so a value arriving moves nothing.
class ProgressRing extends StatelessWidget {

  static const double _size = 40;
  static const double _stroke = 5;

  /// forui's spinner, grown with the ring rather than left at forui's own 16.
  static const double _spinnerSize = 29;

  /// How long the arc takes to catch up with a new [value]. Short: values
  /// arrive many times a second, and a slow ring would lag the download.
  static const Duration _catchUp = Duration(milliseconds: 150);

  /// The share that is done, or null to show a spinner.
  final double? value;

  const ProgressRing({required this.value, super.key});

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final colors = context.theme.colors;

    return SizedBox.square(
      dimension: _size,
      child: value == null
          ? const Center(
              child: FCircularProgress(
                style: FCircularProgressStyleDelta.delta(iconStyle: IconThemeDataDelta.delta(size: _spinnerSize)),
              ),
            )
          : Semantics(
              value: '${(value.clamp(0, 1) * 100).round()}%',
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value.clamp(0, 1).toDouble()),
                duration: context.motion(_catchUp),
                builder: (context, shown, _) => CustomPaint(
                  // The spinner's own colour, so the two read as one control.
                  painter: _RingPainter(value: shown, track: colors.border, arc: colors.mutedForeground),
                ),
              ),
            ),
    );
  }

}

class _RingPainter extends CustomPainter {

  final double value;
  final Color track;
  final Color arc;

  const _RingPainter({required this.value, required this.track, required this.arc});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(ProgressRing._stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ProgressRing._stroke;

    canvas
      ..drawOval(rect, paint..color = track)
      // From twelve o'clock, clockwise.
      ..drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, paint..color = arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.track != track || old.arc != arc;

}
