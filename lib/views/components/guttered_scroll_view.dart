import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';

/// A [SingleChildScrollView] that leaves its scrollbar room beside the content.
///
/// [AppScrollbar.gutter] is added to [padding] on the side the bar is drawn on:
/// the end of a vertical view, the bottom of a horizontal one. The view is that
/// much wider or taller than its content, so a caller that wants the content
/// where it was MUST take the gutter out of the whitespace beside it.
class GutteredScrollView extends StatelessWidget {

  final Axis scrollDirection;

  /// The content's own padding, inside the scroll view.
  final EdgeInsetsGeometry padding;

  final Widget child;

  const GutteredScrollView({
    required this.child,
    this.scrollDirection = Axis.vertical,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: scrollDirection,
      padding: padding.add(switch (scrollDirection) {
        Axis.vertical => const EdgeInsetsDirectional.only(end: AppScrollbar.gutter),
        Axis.horizontal => const EdgeInsets.only(bottom: AppScrollbar.gutter),
      }),
      child: child,
    );
  }

}
