import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/views/components/hover_tip.dart';

/// Says [message] about [child] on hover, but only while [child] is narrower
/// than it wants to be.
///
/// For a one-line text that is cut with an ellipsis when it runs out of room:
/// a crumb of the trail. The tip is the part of it the reader cannot see, so a
/// text that fits has nothing to add and opens none.
///
/// Whether it fits is asked on the hover and not kept. The answer changes with
/// the window, and nothing has to rebuild for a tip nobody is looking at.
///
/// ## What this leans on
///
/// - A one-line [Text] reports the width of its whole line as its max
///   intrinsic width, whatever width it was laid out at. Narrower than that,
///   it is cut.
/// - Everything [HoverTip] puts around [child] is a proxy box, so this widget's
///   own render object has [child]'s size and [child]'s intrinsic width.
/// - forui's tooltip, lifted, only *asks* for the tip through `onChange`.
///   Saying no there leaves it shut.
///
/// [message] MUST be what [child] says in full.
class ShortenedTip extends StatefulWidget {

  final String message;

  final Widget child;

  const ShortenedTip({required this.message, required this.child, super.key});

  @override
  State<ShortenedTip> createState() => _ShortenedTipState();

}

class _ShortenedTipState extends State<ShortenedTip> {

  bool _shown = false;

  bool get _shortened {
    final box = context.findRenderObject();

    return box is RenderBox &&
        box.hasSize &&
        box.getMaxIntrinsicWidth(double.infinity) > box.size.width + precisionErrorTolerance;
  }

  // A method and not a closure: forui compares the callback to tell whether
  // the control changed.
  void _onWanted(bool wanted) {
    if (!mounted) return;

    final shown = wanted && _shortened;
    if (shown != _shown) setState(() => _shown = shown);
  }

  @override
  Widget build(BuildContext context) {
    return HoverTip(
      control: FTooltipControl.lifted(shown: _shown, onChange: _onWanted),
      message: widget.message,
      child: widget.child,
    );
  }

}
