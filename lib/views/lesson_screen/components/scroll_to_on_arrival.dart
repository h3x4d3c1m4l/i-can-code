import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/components/app_header.dart';

/// Scrolls the page until [child] starts just under the bar, when it appears
/// on a page that is already showing and again whenever [token] changes.
///
/// ## What this leans on
///
/// - The scroll view is found from this widget's own context, so it moves the
///   page on a step that scrolls as one and the column on a two-column step.
///   No `GlobalKey`: `StepTransition` keeps the step that is leaving mounted,
///   and two copies of one key throw.
/// - A scroll view has no content dimensions until its first layout. Mounted
///   before that, [child] came with the page, and a page opens at its top.
/// - `ScrollPosition.animateTo` asserts on a zero duration, which is what
///   `context.motion` answers for a reader who asked for less motion. That
///   reader gets `jumpTo`.
class ScrollToOnArrival extends StatefulWidget {

  /// How far below the top of the scroll view [child] comes to rest. The bar is
  /// drawn over the page, so its height is part of it.
  static const double clearance = AppHeader.height + 24;

  static const Duration duration = Duration(milliseconds: 350);

  /// What [child] is showing, where one mounted [child] can show a second
  /// thing. Compared by identity, so that two runs with the same outcome both
  /// scroll.
  final Object? token;

  final Widget child;

  const ScrollToOnArrival({required this.child, this.token, super.key});

  @override
  State<ScrollToOnArrival> createState() => _ScrollToOnArrivalState();

}

class _ScrollToOnArrivalState extends State<ScrollToOnArrival> {

  @override
  void initState() {
    super.initState();

    // Not laid out yet, so this came with the page, which opens at its top.
    final page = context.findAncestorStateOfType<ScrollableState>()?.position;
    if (page != null && !page.hasContentDimensions) return;

    _scrollAfterLayout();
  }

  @override
  void didUpdateWidget(ScrollToOnArrival oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.token, oldWidget.token)) _scrollAfterLayout();
  }

  /// [widget.child] has no position until the frame that builds it has been
  /// laid out.
  void _scrollAfterLayout() => WidgetsBinding.instance.addPostFrameCallback((_) => _scroll());

  void _scroll() {
    if (!mounted) return;

    final object = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (object == null || position == null) return;

    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return;

    // Clamped, so a short page stops at its end instead of overscrolling.
    final target = (viewport.getOffsetToReveal(object, 0).offset - ScrollToOnArrival.clearance).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final duration = context.motion(ScrollToOnArrival.duration);

    if (duration == Duration.zero) {
      position.jumpTo(target);
    } else {
      unawaited(position.animateTo(target, duration: duration, curve: Curves.easeOutCubic));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

}
