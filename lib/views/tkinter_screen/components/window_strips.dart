import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:i_can_code/services/vm/vm_runtime.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/tkinter_screen/components/window_frame.dart';

/// A title strip with a close button over every window the outer [WindowFrame]
/// does not name, drawn on top of the screen at that window's own place.
///
/// The guest runs no window manager, so a second `Toplevel` arrives with no
/// title, no close button and, unless the program placed it, at +0+0 over the
/// one before it. The frame can name only one window, so the rest are named
/// here.
///
/// A strip sits just above its window when the screen has room for it there,
/// and over the window's top edge when it does not, which is what a window at
/// the top of the screen gets. It never leaves the screen sideways.
class WindowStrips extends StatelessWidget {

  static const double height = 26;

  /// Enough for a close button and a few letters of title.
  static const double minWidth = 96;

  /// The windows to name, bottom to top. The frame's own MUST NOT be among
  /// them, and neither may a window that is not mapped.
  final List<VmWindow> windows;

  /// The part of the guest's screen the page shows, in guest pixels.
  final Rect region;

  /// Guest pixels to logical pixels.
  final double scale;

  final String closeLabel;
  final String untitledLabel;
  final void Function(int xid) onClose;

  const WindowStrips({
    required this.windows,
    required this.region,
    required this.scale,
    required this.closeLabel,
    required this.untitledLabel,
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final box = region.size * scale;

    return Stack(
      children: [
        for (final window in windows)
          if (_placeOf(window, box) case final Rect place)
            Positioned(
              left: place.left,
              top: place.top,
              width: place.width,
              height: place.height,
              child: _Strip(
                title: window.title.isEmpty ? untitledLabel : window.title,
                closeLabel: closeLabel,
                onClose: () => onClose(window.xid),
              ),
            ),
      ],
    );
  }

  /// Where the strip for [window] goes, or null when it would fall outside the
  /// shown region entirely.
  Rect? _placeOf(VmWindow window, Size box) {
    final left = (window.x - region.left) * scale;
    final top = (window.y - region.top) * scale;
    final double width = math.max(minWidth, window.width * scale);
    if (left >= box.width || top >= box.height) return null;

    final double shown = math.min(width, box.width);
    final double start = left.clamp(0.0, math.max(0.0, box.width - shown));
    return Rect.fromLTWH(start, math.max(0.0, top >= height ? top - height : top), shown, height);
  }

}

class _Strip extends StatelessWidget {

  final String title;
  final String closeLabel;
  final VoidCallback onClose;

  const _Strip({required this.title, required this.closeLabel, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;
    final text = context.appTheme.text;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.codeBackground,
        shape: squircle(kChipCornerRadius, side: BorderSide(color: colors.codeMuted.withValues(alpha: 0.5))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
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
            SizedBox.square(
              dimension: WindowStrips.height,
              child: FittedBox(child: WindowCloseButton(label: closeLabel, onPress: onClose)),
            ),
          ],
        ),
      ),
    );
  }

}
