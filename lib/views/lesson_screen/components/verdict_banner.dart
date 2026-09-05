import 'package:flutter/widgets.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The coloured panel a step's verdict is delivered in: a failed check, a
/// traceback, a "Goed!".
///
/// Only the fill is passed in. Every one of them is a `*Surface` token, which
/// is what makes the page's own ink legible on all of them — see
/// `AppSemanticColors` on why a foreground is never picked at the call site.
class VerdictBanner extends StatelessWidget {

  final Color background;
  final Widget child;

  const VerdictBanner({required this.background, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(color: background, shape: squircle(kCardCornerRadius)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), child: child),
    );
  }

}
