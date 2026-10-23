import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/views/components/hover_tip.dart';

/// Says [message] about [child] on hover, but only while a text in [child] is
/// cut short.
///
/// For text that ends in an ellipsis when it runs out of room: a crumb of the
/// trail, or the title and subtitle on a catalog tile. The tip is the part the
/// reader cannot see, so text that fits has nothing to add and opens none.
///
/// Whether it fits is asked on the hover and not kept. The answer changes with
/// the window, and nothing has to rebuild for a tip nobody is looking at.
///
/// ## What this leans on
///
/// - A text that may wrap is cut only by its line clamp, which its
///   [RenderParagraph] reports as `didExceedMaxLines`.
/// - A one-line text reports the width of its whole line as its max intrinsic
///   width, whatever width it was laid out at. Narrower than that, it is cut.
///   A wrapped text always reports more than its width, which is why the two
///   are told apart.
/// - forui's tooltip, lifted, only *asks* for the tip through `onChange`.
///   Saying no there leaves it shut.
///
/// [message] MUST say in full every text under [child] that can be cut.
class ShortenedTip extends StatefulWidget {

  final String message;

  final Widget child;

  /// See [HoverTip.maxWidth].
  final double? maxWidth;

  const ShortenedTip({required this.message, required this.child, this.maxWidth, super.key});

  @override
  State<ShortenedTip> createState() => _ShortenedTipState();

}

class _ShortenedTipState extends State<ShortenedTip> {

  bool _shown = false;

  bool get _shortened {
    var cut = false;

    void visit(RenderObject object) {
      if (cut) return;
      if (object is RenderParagraph && object.hasSize && _isCut(object)) {
        cut = true;
        return;
      }
      object.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root != null) visit(root);

    return cut;
  }

  static bool _isCut(RenderParagraph paragraph) => paragraph.softWrap && paragraph.maxLines != 1
      ? paragraph.didExceedMaxLines
      : paragraph.getMaxIntrinsicWidth(double.infinity) > paragraph.size.width + precisionErrorTolerance;

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
      maxWidth: widget.maxWidth,
      child: widget.child,
    );
  }

}
