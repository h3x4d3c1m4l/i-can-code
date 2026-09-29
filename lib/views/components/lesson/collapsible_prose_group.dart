import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

/// A `###` heading and everything under it, folded away by pressing the
/// heading.
///
/// The chevron is always drawn, muted, and brightens on hover or focus. Showing
/// it on hover alone would hide the affordance on a touch screen, and a folded
/// group would then look like a heading whose content had gone missing.
///
/// The chevron sits in a [gutter] that is part of this widget's own box, and
/// the heading and prose start after it. Everything the student can press is
/// therefore inside the box that receives the press — a chevron painted outside
/// it, by a [Stack] or a [Transform], would be drawn but never hit-tested.
///
/// Keeping the prose aligned with the rest of the step is the caller's half of
/// the deal: the page it sits on MUST give back [gutter] of its own left
/// padding, so that the text still lands where it would without a chevron. See
/// `LessonScreenView`.
class CollapsibleProseGroup extends StatefulWidget {

  /// How far into the margin the chevron reaches.
  static const double gutter = 26;

  /// The heading's text, without its `###`.
  final String heading;

  final TextStyle headingStyle;

  /// The prose under the heading, already rendered.
  final Widget child;

  /// Space above and below the heading. The caller owns it because the first
  /// group in a step has nothing to be spaced from.
  final EdgeInsets headingPadding;

  /// Whether the group starts folded. An author sets this per heading; the
  /// student's own folding is not remembered between visits either way.
  final bool initiallyCollapsed;

  const CollapsibleProseGroup({
    required this.heading,
    required this.headingStyle,
    required this.child,
    this.headingPadding = EdgeInsets.zero,
    this.initiallyCollapsed = false,
    super.key,
  });

  @override
  State<CollapsibleProseGroup> createState() => _CollapsibleProseGroupState();

}

class _CollapsibleProseGroupState extends State<CollapsibleProseGroup> with SingleTickerProviderStateMixin {

  static const double _chevronSize = 18;

  /// A group is open unless its heading asked to start folded. Set outright
  /// rather than animated, so a step does not unfold itself on arrival.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: widget.initiallyCollapsed ? 0 : 1,
  );

  late final Animation<double> _fold = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  late bool _expanded = !widget.initiallyCollapsed;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FTappable(
          semanticsButton: true,
          onPress: _toggle,
          builder: (context, states, _) {
            final lit = states.contains(FTappableVariant.hovered) || states.contains(FTappableVariant.focused);

            return Padding(
              padding: widget.headingPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: CollapsibleProseGroup.gutter,
                    // Measured off the heading's own metrics, so the chevron
                    // sits on the first line of a heading that wrapped rather
                    // than in the middle of it.
                    height: (widget.headingStyle.fontSize ?? _chevronSize) * (widget.headingStyle.height ?? 1.4),
                    child: AnimatedBuilder(
                      animation: _fold,
                      builder: (context, _) => Transform.rotate(
                        // Down when open, right when folded.
                        angle: (_fold.value - 1) * math.pi / 2,
                        child: Icon(
                          FLucideIcons.chevronDown,
                          size: _chevronSize,
                          color: lit ? colors.foreground : colors.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: Text(widget.heading, style: widget.headingStyle)),
                ],
              ),
            );
          },
        ),
        // [FCollapsible] clips to its own render box rather than shrinking the
        // child, so the prose keeps its full width while it folds and the text
        // does not reflow on the way.
        AnimatedBuilder(
          animation: _fold,
          builder: (context, child) => FCollapsible(value: _fold.value, child: child!),
          child: Padding(
            // Lines the prose up with the heading's text, past the chevron.
            padding: const EdgeInsets.only(left: CollapsibleProseGroup.gutter),
            child: widget.child,
          ),
        ),
      ],
    );
  }

}
