import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// Says [message] about [child] the moment the pointer is over it, or the
/// keyboard is on it.
///
/// For a control whose press is a move somewhere and whose face cannot say
/// where: a segment of the progress bar, a back chevron.
///
/// An [FTooltip] and not the popover `HintMark` uses. forui's tooltip hides on
/// every pointer down, which rules it out for a hint that opens on a press and
/// is exactly what this one wants: the tip is gone by the time the place it
/// named is drawn.
///
/// The tip is not part of [child]'s semantics. A caller MUST say the same
/// thing there.
class HoverTip extends StatelessWidget {

  final String message;

  final Widget child;

  /// Who decides whether the tip is up. forui does, unless a caller lifts it
  /// to keep the tip shut on a hover that has nothing to say.
  final FTooltipControl control;

  /// The widest the tip gets before its text wraps. Null leaves forui's cap,
  /// which is the viewport.
  final double? maxWidth;

  const HoverTip({
    required this.message,
    required this.child,
    this.control = const FTooltipControl.managed(),
    this.maxWidth,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FTooltip(
      control: control,
      // No dwell time: forui waits out half a second, and on a control that is
      // about to be pressed that reads as the hover doing nothing at all.
      style: FTooltipStyleDelta.delta(
        hoverEnterDuration: Duration.zero,
        constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth!),
      ),
      // forui's long press is a recogniser around the child. It wins the arena
      // from the child's own tap after half a second, so a button held down a
      // moment too long would show its tip and never fire.
      longPress: false,
      tipBuilder: (context, _) => Text(message),
      child: child,
    );
  }

}
