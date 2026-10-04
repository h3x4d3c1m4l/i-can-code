import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/extensions/color_extension.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/catalog_screen/components/bar_clearance_sliver.dart';
import 'package:i_can_code/views/catalog_screen/components/catalog_group_heading.dart';

/// A [CatalogGroupHeading] that sticks under the bar while the lessons of its
/// group pass under it, so a student scrolling the catalog can always tell
/// which week they are in.
///
/// It MUST be the first sliver of a [SliverMainAxisGroup] that holds its
/// lessons: the group is what pushes it off once the last of them has gone by.
/// And a [BarClearanceSliver] MUST come before it, or it sticks behind the bar.
///
/// Stuck, it floats over the cards as a small label of its own instead of
/// stretching across the page. A band the width of the page would cut the
/// cards off sharp along its bottom edge.
class StickyGroupHeading extends StatelessWidget {

  /// The space above the heading that belongs to the sliver itself. It is what
  /// keeps a stuck heading clear of the bar's edge, so the caller lays out the
  /// rest of the gap it wants above.
  static const double topGap = 16;

  static const double _bottomGap = 14;

  /// How far the label's surface reaches past the heading's own text. Drawn
  /// outside the text's box, so the words do not move when it appears.
  static const EdgeInsets _labelPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 6);

  /// The design's smallest radius. A chip's would bow inward on a label only
  /// one line of small capitals tall.
  static const double _cornerRadius = 8;

  /// The surface coming and going. Matters of taste, like the shadow under it.
  static const Duration _fade = Duration(milliseconds: 160);
  static const double _shadowDarken = 0.3;
  static const double _shadowOpacity = 0.35;
  static const double _shadowBlur = 10;
  static const double _shadowDrop = 2;

  final String label;

  const StickyGroupHeading(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilt during layout, on every scroll that moves it. The constraints
    // are the only place that says whether the heading is where the list put
    // it or held up by the pin: past its spot, or painted lower than it.
    return SliverLayoutBuilder(
      builder: (context, constraints) => PinnedHeaderSliver(
        child: Padding(
          padding: const EdgeInsets.only(top: topGap, bottom: _bottomGap),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _buildLabel(context, stuck: constraints.scrollOffset > 0 || constraints.overlap > 0),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, {required bool stuck}) {
    final colors = context.theme.colors;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          left: -_labelPadding.left,
          top: -_labelPadding.top,
          right: -_labelPadding.right,
          bottom: -_labelPadding.bottom,
          child: AnimatedOpacity(
            opacity: stuck ? 1 : 0,
            duration: context.motion(_fade),
            curve: Curves.easeOut,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.card,
                shape: squircle(_cornerRadius, side: BorderSide(color: colors.border)),
                shadows: [
                  BoxShadow(
                    color: colors.border.darken(_shadowDarken).withValues(alpha: _shadowOpacity),
                    blurRadius: _shadowBlur,
                    offset: const Offset(0, _shadowDrop),
                  ),
                ],
              ),
            ),
          ),
        ),
        CatalogGroupHeading(label),
      ],
    );
  }

}
