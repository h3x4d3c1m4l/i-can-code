import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// A question mark that explains the thing it sits beside.
///
/// For a label the reader may not know the meaning of — the catalog's
/// *Verdieping* heading, the same word as a badge on a step. The explanation is
/// tucked behind the mark rather than set as prose, because it answers a
/// question most readers will never have and a sentence that sits there
/// permanently competes with what it is introducing.
///
/// **An [FPopover] and not an [FTooltip]**, even though it reads like one.
/// forui's tooltip wraps its child in a `Listener` that hides the tip on *every*
/// pointer down, so a tap opens and closes it within one gesture and nothing is
/// ever read. A popover adds no gesture of its own, which leaves room for all
/// three ways in: the pointer through the [MouseRegion] below, a tap or Enter
/// through the [FTappable], and a tap anywhere else to dismiss.
class HintMark extends StatefulWidget {

  /// What the explanation says. A sentence or two.
  final String message;

  /// Names the mark for a screen reader. A **question**, because that is what
  /// pressing it answers — "Wat is een verdieping?" rather than "Uitleg".
  final String semanticsLabel;

  const HintMark({required this.message, required this.semanticsLabel, super.key});

  @override
  State<HintMark> createState() => _HintMarkState();

}

class _HintMarkState extends State<HintMark> with SingleTickerProviderStateMixin {

  /// Smaller than whatever it sits beside: it is an aside, and a mark set to
  /// match would read as part of the label.
  static const double _size = 18;

  /// Room for two lines and no more. An explanation as wide as the page is a
  /// paragraph that happens to float.
  static const double _panelWidth = 300;

  static const EdgeInsets _panelPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

  /// Owned here rather than by `FPopoverControl.managed()` for the reason
  /// `SettingsMenu`'s is: the popover does not open itself, so something MUST
  /// open it.
  late final FPopoverController _controller = FPopoverController(vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTheme;
    final colors = context.theme.colors;

    return FPopover(
      popoverAnchor: Alignment.topLeft,
      childAnchor: Alignment.bottomLeft,
      control: FPopoverControl.managed(controller: _controller),
      popoverBuilder: (context, _) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _panelWidth),
        child: Padding(
          padding: _panelPadding,
          child: Text(widget.message, style: tokens.text.bodySmall),
        ),
      ),
      child: MouseRegion(
        // Straight away, with no dwell time: forui's tooltip waits out half a
        // second before it says anything, which on a mark this small reads as
        // nothing happening.
        onEnter: (_) => _controller.show(),
        onExit: (_) => _controller.hide(),
        child: FTappable(
          // `show` and not `toggle`: the pointer is already inside by the time a
          // click lands, so toggling would close what the hover opened and
          // leave it shut until the pointer went away and came back. A tap
          // anywhere else closes it, which is what a touch screen needs.
          onPress: _controller.show,
          semanticsButton: true,
          semanticsLabel: widget.semanticsLabel,
          child: Icon(FLucideIcons.circleQuestionMark, size: _size, color: colors.mutedForeground),
        ),
      ),
    );
  }

}
