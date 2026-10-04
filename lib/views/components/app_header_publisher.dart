import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/components/app_header.dart';
import 'package:i_can_code/views/components/app_header_host.dart';

/// Puts a screen's own header in the app's bar for as long as the screen is up.
///
/// Wraps the screen rather than sitting in it: the bar itself lives above the
/// router (see [AppHeaderHost]), and this is the only thing that reaches it.
/// Below no host — a widget test that builds one screen on its own — it is a
/// pass-through and the screen renders exactly as it did.
///
/// Both the publish and the release are **deferred by a microtask**, for two
/// reasons that happen to want the same thing:
///
/// - The bar is built before the screen is, so filling it from `initState`
///   would rebuild a widget that Flutter has already built this frame.
/// - A screen is disposed *after* its successor is created, so an immediate
///   release could empty a bar the next screen has already filled. Deferring
///   puts the claim and the release in the queue in the order they happened,
///   and the host keeps the claims of every screen still standing.
///
/// It also tells the bar whether this screen's page has content scrolled under
/// it, which is what gives the bar its edge. That is read off the scroll
/// notifications bubbling up from the page, so a screen needs nothing of its
/// own for it. Only a vertical scroll view whose top is under the bar counts:
/// a code editor or a terminal further down the page scrolls inside itself,
/// and nothing of it passes under the bar.
class AppHeaderPublisher extends StatefulWidget {

  final AppHeaderBuilder builder;
  final Widget child;

  const AppHeaderPublisher({required this.builder, required this.child, super.key});

  @override
  State<AppHeaderPublisher> createState() => _AppHeaderPublisherState();

}

class _AppHeaderPublisherState extends State<AppHeaderPublisher> {

  AppHeaderSlot? _slot;

  /// The scroll views of this page that have content under the bar. More than
  /// one, because a lesson's two columns scroll apart.
  final Set<BuildContext> _scrolledUnder = {};

  /// What the bar was last told.
  bool _reported = false;

  bool _reportScheduled = false;
  bool _watchingForGone = false;

  /// Delegates to whichever builder the widget currently carries, so the bar is
  /// published **once**: a screen that rebuilds does not have to hand its
  /// header over again, and the host resolves the current builder either way.
  AppHeaderConfig _resolve(BuildContext context) => widget.builder(context);

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_publish);
  }

  void _publish() {
    if (!mounted) return;
    _slot = AppHeaderScope.of(context)?..publish(this, _resolve);
  }

  @override
  void dispose() {
    final slot = _slot;
    scheduleMicrotask(() => slot?.release(this));
    super.dispose();
  }

  bool _onNotification(Notification notification) {
    switch (notification) {
      // A scroll view announces itself with a metrics notification once it is
      // laid out, so one that opens part way down is heard without a scroll.
      case ScrollNotification(:final metrics, context: final BuildContext scrollable) ||
          ScrollMetricsNotification(:final metrics, context: final scrollable):
        _track(scrollable, metrics);
    }
    return false;
  }

  void _track(BuildContext scrollable, ScrollMetrics metrics) {
    final under = switch (metrics.axisDirection) {
      AxisDirection.down => metrics.extentBefore > 0,
      AxisDirection.up => metrics.extentAfter > 0,
      AxisDirection.left || AxisDirection.right => false,
    };

    if (under && _startsUnderBar(scrollable)) {
      _scrolledUnder.add(scrollable);
      _watchForGone();
    } else {
      _scrolledUnder.remove(scrollable);
    }
    _report();
  }

  bool _startsUnderBar(BuildContext scrollable) {
    final box = scrollable.findRenderObject();
    final page = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || page == null) return false;

    return box.localToGlobal(Offset.zero, ancestor: page).dy < AppHeader.height;
  }

  /// Drops a scroll view that has gone, once per frame for as long as any is
  /// tracked.
  ///
  /// A scroll view that is disposed sends nothing on its way out. A lesson's
  /// step is swapped for the next one that way, and without this the bar would
  /// keep the edge the old step left it until the next scroll.
  void _watchForGone() {
    if (_watchingForGone) return;
    _watchingForGone = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _watchingForGone = false;
      if (!mounted || _scrolledUnder.isEmpty) return;
      _scrolledUnder.removeWhere((scrollable) => !scrollable.mounted);
      _report();
      if (_scrolledUnder.isNotEmpty) _watchForGone();
    });
  }

  /// Deferred for the reason the publish is: a scroll view can be corrected
  /// during layout, and the bar is not to be rebuilt from inside one.
  void _report() {
    if (_reportScheduled) return;
    _reportScheduled = true;
    scheduleMicrotask(() {
      _reportScheduled = false;
      final slot = _slot;
      final scrolledUnder = _scrolledUnder.isNotEmpty;
      if (!mounted || slot == null || scrolledUnder == _reported) return;
      _reported = scrolledUnder;
      slot.reportScrolledUnder(this, scrolledUnder: scrolledUnder);
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(onNotification: _onNotification, child: widget.child);
  }

}
