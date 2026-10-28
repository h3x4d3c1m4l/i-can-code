import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:i_can_code/views/components/scroll_shadows.dart';

/// A card whose content scrolls inside its own rounded edge, and shows that it
/// does: a thumb at rest, and [ScrollShadows] along the edges.
///
/// The card clips, so content cut off by its edge ends in its corners rather
/// than on a straight line, and the shadows end there too. The thumb is drawn
/// inside the card, so [padding] MUST keep the content at least
/// [AppScrollbar.gutter] from the end edge.
class ScrollCard extends StatelessWidget {

  static const EdgeInsets defaultPadding = EdgeInsets.symmetric(horizontal: 26, vertical: 22);

  /// A card on the page, edged in the page's border, or a code card, which
  /// has no edge, like every code card.
  final ScrollSurface surface;

  final EdgeInsetsGeometry padding;

  final Widget child;

  const ScrollCard({
    required this.child,
    this.surface = ScrollSurface.page,
    this.padding = defaultPadding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final (fill, shape) = switch (surface) {
      ScrollSurface.page => (
        context.theme.colors.card,
        squircle(kCardCornerRadius, side: BorderSide(color: context.theme.colors.border)),
      ),
      ScrollSurface.code => (context.appTheme.colors.codeBackground, squircle(kCardCornerRadius)),
    };

    return DecoratedBox(
      decoration: ShapeDecoration(color: fill, shape: shape),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: ScrollShadows(
          surface: surface,
          child: ScrollConfiguration(
            behavior: AppScrollBehavior(surface: surface, thumbAlwaysShown: true),
            child: SingleChildScrollView(
              primary: false,
              padding: padding,
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        ),
      ),
    );
  }

}
