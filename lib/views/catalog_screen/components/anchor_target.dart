import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/routing/catalog_anchor.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/catalog_screen/components/catalog_anchor_scope.dart';

/// A part of the catalog an address can name. Asked for, it brings itself to
/// just under the bar and then lights up: a ring that runs outward from it and
/// fades, twice.
///
/// A pass-through below no [CatalogAnchorScope].
///
/// ## What this leans on
///
/// - `RenderAbstractViewport.getOffsetToReveal` already leaves room for every
///   pinned sliver ahead of the part: the catalog's `BarClearanceSliver`, and
///   the heading stuck over a group's cards. So [clearance] is counted from
///   under those, and not from the top of the scroll view.
/// - That offset comes out of each sliver's scroll extent, so it is exact only
///   because every card is built. A lazy list would be estimating the cards it
///   has not laid out, and the page would come to rest beside the part.
/// - The scroll view is found from this widget's own context and the part from
///   its own render object. No `GlobalKey`, for the reason `TourTarget` gives.
/// - `ScrollPosition.animateTo` asserts on a zero duration, which is what
///   `context.motion` answers for a reader who asked for less motion. That
///   reader gets `jumpTo`, and a ring that stands still.
class AnchorTarget extends StatefulWidget {

  static const Duration scrollDuration = Duration(milliseconds: 450);

  /// The ring. Matters of taste, all of them: how thick it is, how far it
  /// runs before it is gone, how many follow each other, and where the one a
  /// reader who asked for less motion gets stands still.
  static const double _ringWidth = 3;
  static const double _ringTravel = 10;
  static const int _ringCount = 2;
  static const double _ringAtRest = 4;

  /// The anchor this part is the place of. A request for it scrolls here.
  final CatalogAnchor anchor;

  /// An anchor this part lights up along with, without being where the page
  /// goes: the group a lesson's card stands in.
  final CatalogAnchor? alongWith;

  /// How far below the bar, and below the heading stuck under it, the part
  /// comes to rest.
  final double clearance;

  /// The part's corner radius, in the design's numbers, as `squircle` takes it.
  final double radius;

  /// How far outside [child] the ring starts, for a part that looks larger
  /// than its own box.
  final EdgeInsets outset;

  final Widget child;

  const AnchorTarget({
    required this.anchor,
    required this.radius,
    required this.child,
    this.alongWith,
    this.clearance = 0,
    this.outset = EdgeInsets.zero,
    super.key,
  });

  @override
  State<AnchorTarget> createState() => _AnchorTargetState();

}

class _AnchorTargetState extends State<AnchorTarget> {

  CatalogAnchorRequest? _request;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final request = CatalogAnchorScope.of(context);
    if (identical(request, _request)) return;
    _request = request;

    // The part has no position until the frame that builds it has been laid
    // out.
    if (request != null && request.anchor == widget.anchor && request.take()) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_goTo(request)));
    }
  }

  Future<void> _goTo(CatalogAnchorRequest request) async {
    if (!mounted) return;

    final object = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (object == null || position == null) return;

    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return;

    // Clamped, so a part near the end of the page stops where the page does.
    final target = (viewport.getOffsetToReveal(object, 0).offset - widget.clearance).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final duration = context.motion(AnchorTarget.scrollDuration);

    if (duration == Duration.zero) {
      position.jumpTo(target);
    } else {
      await position.animateTo(target, duration: duration, curve: Curves.easeInOutCubic);
    }

    // A second request may have come in while the page was on its way here.
    if (mounted && identical(request, _request)) request.arrived();
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final lit = request != null && (request.anchor == widget.anchor || request.anchor == widget.alongWith);

    // Always a `CustomPaint`, lit or not. Wrapping the child only while it is
    // lit would move it in the tree and throw away its hover and focus.
    return CustomPaint(
      foregroundPainter: lit
          ? _RingPainter(
              ring: request.ring,
              color: context.theme.colors.foreground,
              still: MediaQuery.disableAnimationsOf(context),
              radius: widget.radius,
              outset: widget.outset,
            )
          : null,
      child: widget.child,
    );
  }

}

class _RingPainter extends CustomPainter {

  final Animation<double> ring;
  final Color color;

  /// Whether the reader asked for less motion, and gets one ring that does
  /// not move.
  final bool still;

  final double radius;
  final EdgeInsets outset;

  _RingPainter({
    required this.ring,
    required this.color,
    required this.still,
    required this.radius,
    required this.outset,
  }) : super(repaint: ring);

  @override
  void paint(Canvas canvas, Size size) {
    final progress = ring.value;
    // At rest at either end: not asked for yet, or done.
    if (progress <= 0 || progress >= 1) return;

    final pulse = (progress * AnchorTarget._ringCount) % 1;
    final travel = still ? AnchorTarget._ringAtRest : AnchorTarget._ringTravel * Curves.easeOutCubic.transform(pulse);
    final opacity = still ? 1.0 : 1 - Curves.easeInQuad.transform(pulse);

    final rect = outset.inflateRect(Offset.zero & size).inflate(travel);
    // A negative inset: the ring runs outside the part, on a parallel corner.
    final shape = squircleOf(concentricRadius(radius, inset: -travel), size: rect.shortestSide);

    canvas.drawPath(
      shape.getOuterPath(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = AnchorTarget._ringWidth
        ..color = color.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.ring != ring || old.color != color || old.still != still || old.radius != radius || old.outset != outset;

}
