import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_header_publisher.dart';

/// What a scroll view is drawn on, which decides the colour of its thumb.
enum ScrollSurface {

  /// The page, a card or a dialog.
  page,

  /// The dark code surface, which every preset has.
  code,

}

/// Draws an [AppScrollbar] wherever Flutter would draw its own.
///
/// The app shell puts one round the whole app. A scroll view drawn on the code
/// surface MUST sit under a `ScrollConfiguration` with [ScrollSurface.code],
/// because the page's thumb does not show on dark.
class AppScrollBehavior extends ScrollBehavior {

  final ScrollSurface surface;

  /// Shows the thumb at rest as well, for a scroll view whose overflow is easy
  /// to miss. It still shows nothing where there is nothing to scroll.
  final bool thumbAlwaysShown;

  const AppScrollBehavior({this.surface = ScrollSurface.page, this.thumbAlwaysShown = false});

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return switch (getPlatform(context)) {
      TargetPlatform.linux || TargetPlatform.macOS || TargetPlatform.windows => AppScrollbar(
        controller: details.controller,
        surface: surface,
        thumbAlwaysShown: thumbAlwaysShown,
        child: child,
      ),
      // As Flutter's own: a touch screen draws no scrollbar.
      TargetPlatform.android || TargetPlatform.fuchsia || TargetPlatform.iOS => child,
    };
  }

  @override
  bool shouldNotify(AppScrollBehavior oldDelegate) =>
      surface != oldDelegate.surface || thumbAlwaysShown != oldDelegate.thumbAlwaysShown;

}

/// The app's scrollbar: a pill that keeps clear of both ends of its track and
/// of the bar over the page.
///
/// It is drawn over the edge of its scroll view, as every Flutter scrollbar is.
/// What keeps it off the content is room left for it, [gutter] wide.
/// [GutteredScrollView] leaves that room.
///
/// A pill and not a squircle, the way `CompletedBadge` is a circle: the rule is
/// about corners, and a thumb this thin has none.
class AppScrollbar extends RawScrollbar {

  /// The room a scrollbar takes beside its scroll view's content.
  ///
  /// Content MUST keep this far from the scroll view's edge on the side the bar
  /// is drawn on, or the bar is drawn over it.
  static const double gutter = _thumbThickness + 2 * _sideMargin;

  static const double _thumbThickness = 6;

  /// Between the thumb and the edge of the scroll view, and the same again on
  /// the content's side.
  static const double _sideMargin = 4;

  /// Between the thumb and either end of its track. The thumb still covers the
  /// whole scroll range: the track is what gets shorter.
  static const double _endMargin = 8;

  final ScrollSurface surface;

  const AppScrollbar({
    required super.child,
    super.controller,
    this.surface = ScrollSurface.page,
    bool thumbAlwaysShown = false,
    super.key,
  }) : super(
        thumbVisibility: thumbAlwaysShown,
        thickness: _thumbThickness,
        shape: const StadiumBorder(),
        crossAxisMargin: _sideMargin,
        mainAxisMargin: _endMargin,
      );

  @override
  RawScrollbarState<AppScrollbar> createState() => _AppScrollbarState();

}

class _AppScrollbarState extends RawScrollbarState<AppScrollbar> {

  /// How far down from the top of the track the bar covers it.
  double _barClearance = 0;

  @override
  void updateScrollbarPainter() {
    super.updateScrollbarPainter();
    scrollbarPainter
      ..color = switch (widget.surface) {
        ScrollSurface.page => context.theme.colors.mutedForeground,
        ScrollSurface.code => context.appTheme.colors.codeMuted,
      }
      // In place of the MediaQuery padding RawScrollbar falls back on. A touch
      // screen, the only place that has any, draws no scrollbar at all.
      ..padding = EdgeInsets.only(top: _barClearance);
  }

  @override
  Widget build(BuildContext context) {
    // Outside the listeners RawScrollbar puts round its scroll view, so the
    // painter has taken the new metrics by the time this measures.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _measure,
      child: super.build(context),
    );
  }

  /// A scroll view sends one of these once it is laid out and again whenever
  /// its size changes, which is when it can have moved under the bar.
  bool _measure(ScrollMetricsNotification notification) {
    final clearance = switch (notification.metrics.axis) {
      Axis.vertical => AppHeaderPublisher.clearanceOf(context),
      Axis.horizontal => 0.0,
    };
    if (clearance != _barClearance) {
      _barClearance = clearance;
      scrollbarPainter.padding = EdgeInsets.only(top: clearance);
    }
    return false;
  }

}
