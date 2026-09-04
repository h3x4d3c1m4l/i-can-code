import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';

/// Swaps one widget for another by fading the old one out and *then* the new
/// one in, in the same place.
///
/// Not a crossfade: two lines of text at half opacity on top of each other read
/// as a rendering fault rather than as a change. The sequence is one animation
/// all the same — both children run over [_duration], the outgoing one over its
/// first half and the incoming one over its second, which is what the two
/// [Interval]s below do to [AnimatedSwitcher]'s single controller.
///
/// A null [child] fades whatever is showing out and puts nothing in its place.
class FadeThrough extends StatelessWidget {

  /// The whole swap, both halves together. Public because a caller that
  /// animates *around* one of these — a width that changes with the content —
  /// has to agree with it.
  static const Duration duration = Duration(milliseconds: 260);

  /// **MUST carry a key that changes when the content does.** Two widgets of
  /// the same type and key are an update to [AnimatedSwitcher], not a swap, so
  /// content that changed under an unchanged key never fades — which is what
  /// keeps a progress bar from flashing every time it advances.
  final Widget? child;

  const FadeThrough({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: context.motion(duration),
      switchInCurve: const Interval(0.5, 1, curve: Curves.easeOut),
      switchOutCurve: const Interval(0.5, 1, curve: Curves.easeIn),
      // Anchored at the start rather than centred, so a trail that grows a
      // level does not slide sideways while it fades.
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }

}
