import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';

/// Moves one step of a lesson aside and brings the next one in, in the
/// direction the student is travelling: forward, the step leaving goes out to
/// the left and the one arriving comes in from the right.
///
/// [child] MUST carry a key that changes with the step — that key is the only
/// thing that tells one step from the next, since every step is the same widget
/// underneath.
///
/// ## What this leans on
///
/// [AnimatedSwitcher] hands the same [AnimatedSwitcher.transitionBuilder] both
/// children: the one arriving, whose animation runs forward, and the one
/// leaving, whose animation is the same one in reverse. Nothing in the call
/// says which is which — so a naive builder gives both the same offset and the
/// step leaving slides *back the way the new one came*.
///
/// Two things make the direction come out right:
///
/// - **The builder compares the child it is given against the current one**, by
///   key, and gives the other one an offset on the opposite side.
/// - **It is a new closure on every build.** `_AnimatedSwitcherState` rebuilds
///   the transition of every child it is still animating out, but *only* when
///   the builder is not the same instance as last time. A builder hoisted to a
///   field or a static would leave the outgoing step on the direction it
///   arrived with.
class StepTransition extends StatelessWidget {

  /// The whole move. Long enough to read as travel rather than as a flash,
  /// short enough not to sit between the student and the next step.
  static const Duration _duration = Duration(milliseconds: 260);

  /// How far a step travels, as a fraction of the width it is given. A step is
  /// a page of prose, so it slides a little and fades the rest of the way; a
  /// full-width slide would read as a carousel.
  static const double _travel = 0.035;

  /// Which way the student is going.
  final bool forward;

  final Widget child;

  const StepTransition({required this.forward, required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final current = child.key;

    return ClipRect(
      child: AnimatedSwitcher(
        duration: context.motion(_duration),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        // Both steps are laid out to the full size of the screen, rather than
        // to their own: the default builder centres loose children, which lets
        // a short step size itself to its content and jump as it arrives.
        layoutBuilder: (currentChild, previousChildren) => Stack(
          fit: StackFit.expand,
          children: [...previousChildren, ?currentChild],
        ),
        transitionBuilder: (child, animation) {
          final arriving = child.key == current;
          final side = forward ? _travel : -_travel;

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              // The tween is read at `animation == 0` in both directions: for
              // the step arriving that is where it starts, and for the step
              // leaving — whose animation runs down to 0 — it is where it ends
              // up. So `begin` is "the far side", whichever child this is.
              position: Tween(
                begin: Offset(arriving ? side : -side, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: child,
      ),
    );
  }

}
