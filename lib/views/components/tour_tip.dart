import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/app_button.dart';

/// One stop of an introduction: what the lit control does, and the way on.
///
/// Drawn under the control it explains, with a beak pointing up at it.
class TourTip extends StatelessWidget {

  /// The widest a tip gets. Narrower windows get their own width less a gutter.
  static const double maxWidth = 380;

  static const double beakWidth = 18;
  static const double beakHeight = 9;

  final String text;

  /// This stop, counted from 1.
  final int stop;

  final int stopCount;

  /// Where the beak points, in the tip's own coordinates.
  final double beakX;

  /// Null on a stop the reader moves past by pressing the lit control itself.
  final VoidCallback? onNext;

  /// Ends the introduction early. Not offered on the last stop, where "Klaar"
  /// says the same thing.
  final VoidCallback onSkip;

  const TourTip({
    required this.text,
    required this.stop,
    required this.stopCount,
    required this.beakX,
    required this.onNext,
    required this.onSkip,
    super.key,
  });

  bool get _last => stop == stopCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final text = context.appTheme.text;

    return Semantics(
      container: true,
      // Announced on every stop, not only the first: the tip is rebuilt in
      // place, so nothing else tells a screen reader it now says something new.
      liveRegion: true,
      // Not a FocusScope: Tab would then stay inside the tip, and on the first
      // stop the one control the reader has to reach is outside it.
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(left: beakX - beakWidth / 2),
              child: CustomPaint(
                size: const Size(beakWidth, beakHeight),
                painter: _BeakPainter(colors.card),
              ),
            ),
            DecoratedBox(
              decoration: ShapeDecoration(color: colors.card, shape: squircle(kCardCornerRadius)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.localizations.appHeader_tourStop(stop, stopCount),
                      style: text.bodySmall.copyWith(color: colors.mutedForeground),
                    ),
                    const SizedBox(height: 6),
                    Text(this.text, style: text.body.copyWith(color: colors.foreground)),
                    const SizedBox(height: 18),
                    _buildActions(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final colors = context.theme.colors;

    // A Wrap, so a narrow window breaks the row rather than overflowing it.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        if (!_last)
          // Quiet, the way "Meer confetti" is: skipping is always there, but it
          // is not what the tip is asking for.
          FTappable(
            semanticsButton: true,
            // The only control on a stop without a Next, so the keyboard lands
            // somewhere inside the tip either way.
            autofocus: onNext == null,
            onPress: onSkip,
            builder: (context, states, child) => Opacity(
              opacity: states.contains(FTappableVariant.hovered) ? 1 : 0.7,
              child: child,
            ),
            child: Text(
              context.localizations.appHeader_tourSkip,
              style: context.appTheme.text.bodySmall.copyWith(color: colors.mutedForeground),
            ),
          ),
        if (onNext case final VoidCallback onNext)
          AppButton(
            icon: _last ? FLucideIcons.check : FLucideIcons.chevronRight,
            iconSide: AppButtonIconSide.trailing,
            autofocus: true,
            onPress: onNext,
            child: Text(_last ? context.localizations.appHeader_tourDone : context.localizations.appHeader_tourNext),
          ),
      ],
    );
  }

}

/// A plain triangle. It has no rounded corner, so the squircle rule does not
/// reach it.
class _BeakPainter extends CustomPainter {

  final Color color;

  const _BeakPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BeakPainter oldDelegate) => color != oldDelegate.color;

}
