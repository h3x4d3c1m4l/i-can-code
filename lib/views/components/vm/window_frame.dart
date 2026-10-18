import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// How far to scale [guest] pixels of the guest's screen into [available]
/// logical pixels on a display of [devicePixelRatio].
///
/// Never above 1: past that the screen only gets blurrier and takes the page
/// from the editor. Below 1 it prefers a scale at which every guest pixel covers
/// a whole number of device pixels, which is the only size the browser draws
/// without resampling, as long as that costs no more than [maxShrink] of the
/// size that fits. 0.8 on a 1.25 display is 640 × 480 and sharp; 0.83 is the
/// same screen smeared.
double displayScale({
  required Size available,
  required Size guest,
  required double devicePixelRatio,
  double maxShrink = 0.15,
}) {
  final fit = math.min(1.0, math.min(available.width / guest.width, available.height / guest.height));
  if (!fit.isFinite || fit <= 0) return 0;

  final devicePixels = (fit * devicePixelRatio + 1e-9).floor();
  if (devicePixels >= 1) {
    final sharp = devicePixels / devicePixelRatio;
    if (sharp >= fit * (1 - maxShrink)) return sharp;
  }
  return fit;
}

/// Builds what a [WindowFrame] holds, which the frame lays out at exactly [box]
/// logical pixels: the region times [scale], or with no region the frame's
/// empty size and a [scale] of 1.
///
/// It runs at layout, so it MUST NOT read an observable: no Observer above it
/// would see the read.
typedef WindowFrameBuilder = Widget Function(BuildContext context, Size box, double scale);

/// The frame the app draws around the program's windows: a title strip with a
/// close button, and a bezel.
///
/// Drawn by Flutter because the guest runs no window manager, so nothing in it
/// would draw a title bar or offer a way to close a window.
///
/// Hugs the part of the guest's screen it shows, [region], scaled by
/// [displayScale] into the room it is given, and is never narrower than
/// [minWidth], where the region sits centred. With no region it takes
/// [emptySize], or as much of it as fits. The screen sits inside a bezel rather
/// than under the frame's rounded corners, which would otherwise need a clip
/// over the platform view.
class WindowFrame extends StatelessWidget {

  /// The strip's height, which does not change with what is in it.
  static const double stripHeight = 44;

  /// Dark card around the screen. Wide enough that the squircle's corners never
  /// reach the screen's square ones.
  static const double bezel = 10;

  /// The inside of a frame with no window to show: room for the loading panel,
  /// and a place the first window visibly arrives in.
  static const Size emptySize = Size(480, 300);

  /// The least width of the inside, so that the strip keeps room for a title
  /// beside the way out and the close button over a window narrower than that.
  static const double minWidth = 320;

  /// The narrowest the title gets while the strip states the way out.
  static const double _minTitleWidth = 48;

  /// The title of the window it frames, or what stands in for one.
  final String title;

  /// Null while there is no window to close.
  final VoidCallback? onClose;

  final String closeLabel;

  /// Shown at the right of the strip while the screen has the keyboard: the way
  /// out, which WCAG 2.1.2 wants stated.
  final String? hint;

  /// The screen has the keyboard, which the frame shows with an edge.
  final bool focused;

  /// The size of the part of the guest's screen shown, in guest pixels. Null
  /// while there is none to show.
  final Size? region;

  /// Where the frame sits in the room it is given. Top centre by default, so a
  /// window that grows does not walk up the page it is part of; a dialog holds
  /// it in the middle instead.
  final Alignment alignment;

  final WindowFrameBuilder builder;

  const WindowFrame({
    required this.title,
    required this.closeLabel,
    required this.builder,
    this.region,
    this.onClose,
    this.hint,
    this.focused = false,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);

    // Reads nothing observable: the title, hint and region are decided by the
    // caller, whose own Observer tracks them, and the builder promises the same.
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = Size(
          math.max(0, constraints.maxWidth - 2 * bezel),
          math.max(0, constraints.maxHeight - stripHeight - bezel),
        );
        final region = this.region;
        final scale = region == null
            ? 1.0
            : displayScale(available: available, guest: region, devicePixelRatio: devicePixelRatio);
        final box = region == null
            ? Size(math.min(emptySize.width, available.width), math.min(emptySize.height, available.height))
            : region * scale;
        final inside = math.max(box.width, math.min(minWidth, available.width));

        // Loose, so a column that stretches its children does not stretch the
        // frame past the screen it holds. Centred across, because a small
        // window hugged at the start edge leaves the page looking unbalanced.
        return Align(
          alignment: alignment,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: colors.codeBackground,
              shape: squircle(
                kCardCornerRadius,
                // Always 2 wide, so gaining focus changes a colour and not a size.
                side: BorderSide(color: focused ? colors.codeMuted : const Color(0x00000000), width: 2),
              ),
            ),
            child: SizedBox(
              width: inside + 2 * bezel,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: stripHeight, child: _buildStrip(context, inside + 2 * bezel)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(bezel, 0, bezel, bezel),
                    child: Center(
                      heightFactor: 1,
                      child: SizedBox.fromSize(size: box, child: builder(context, box, scale)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStrip(BuildContext context, double width) {
    final colors = context.appTheme.colors;
    final text = context.appTheme.text;
    const padding = EdgeInsets.fromLTRB(18, 0, 6, 0);
    const hintPadding = 12.0;
    // The way out gets its room before the title does: a keyboard user needs all
    // of it to leave, and a title cut short still says which window this is.
    final hintWidth = width - padding.horizontal - WindowCloseButton.size - 2 * hintPadding - _minTitleWidth;

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.codeSmall.copyWith(color: colors.codeForeground),
            ),
          ),
          if (hint case final String hint)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: hintPadding),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: math.max(0, hintWidth)),
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.codeSmall.copyWith(color: colors.codeMuted),
                ),
              ),
            ),
          WindowCloseButton(label: closeLabel, onPress: onClose),
        ],
      ),
    );
  }

}

/// The cross at the right of a strip, the frame's own and the one another
/// window gets. On the code palette rather than the page's, because a strip is
/// part of the dark frame.
class WindowCloseButton extends StatelessWidget {

  static const double size = 32;

  final String label;
  final VoidCallback? onPress;

  const WindowCloseButton({required this.label, required this.onPress, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;
    final enabled = onPress != null;

    return FTappable(
      onPress: onPress,
      semanticsButton: true,
      semanticsLabel: label,
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          color: enabled && states.contains(FTappableVariant.hovered)
              ? colors.codeMuted.withValues(alpha: 0.25)
              : const Color(0x00000000),
          shape: squircleOf(kChipCornerRadius, size: size),
        ),
        child: SizedBox.square(dimension: size, child: Center(child: child)),
      ),
      child: Icon(
        FLucideIcons.x,
        size: 18,
        color: enabled ? colors.codeForeground : colors.codeMuted.withValues(alpha: 0.5),
      ),
    );
  }

}
