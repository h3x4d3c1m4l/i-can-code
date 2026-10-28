import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/color_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';

/// A shadow along the top and the bottom of a vertical scroll view, each while
/// there is more to scroll to on its side.
///
/// A list cut off at a row boundary otherwise looks finished. Each shadow grows
/// in over the first pixels of overflow rather than switching on, so it moves
/// with the list and needs no animation of its own.
///
/// It draws over the whole of its child, so a scroll view with rounded corners
/// MUST be clipped outside it. `ScrollCard` does both.
class ScrollShadows extends StatefulWidget {

  /// What the view is drawn on. A shadow does not show on the dark code
  /// surface, so the content fades into that surface instead.
  final ScrollSurface surface;

  final Widget child;

  const ScrollShadows({required this.child, this.surface = ScrollSurface.page, super.key});

  @override
  State<ScrollShadows> createState() => _ScrollShadowsState();

}

class _ScrollShadowsState extends State<ScrollShadows> {

  /// Drawn after the shadow under the bar's edge. Matters of taste.
  static const double _darken = 0.3;
  static const double _opacity = 0.45;
  static const double _depth = 16;

  static const double _rampDistance = 24;

  /// How strong each shadow is, from 0 to 1.
  double _above = 0;
  double _below = 0;

  /// Takes both kinds of notification: a scroll moves the content, and a
  /// metrics change, which also arrives once the view is first laid out, can
  /// make it overflow or stop doing so.
  bool _onNotification(Notification notification) {
    final ScrollMetrics metrics;
    switch (notification) {
      case ScrollNotification(depth: 0, metrics: final scrolled):
        metrics = scrolled;
      case ScrollMetricsNotification(depth: 0, metrics: final changed):
        metrics = changed;
      default:
        return false;
    }
    if (metrics.axis != Axis.vertical) return false;

    final above = ((metrics.pixels - metrics.minScrollExtent) / _rampDistance).clamp(0.0, 1.0);
    final below = ((metrics.maxScrollExtent - metrics.pixels) / _rampDistance).clamp(0.0, 1.0);
    if (above != _above || below != _below) {
      setState(() {
        _above = above;
        _below = below;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final (color, opacity) = switch (widget.surface) {
      ScrollSurface.page => (context.theme.colors.border.darken(_darken), _opacity),
      ScrollSurface.code => (context.appTheme.colors.codeBackground, 1.0),
    };

    return NotificationListener<Notification>(
      onNotification: _onNotification,
      child: Stack(
        children: [
          widget.child,
          if (_above > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _depth,
              child: _shadow(color, opacity * _above, fromTop: true),
            ),
          if (_below > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: _depth,
              child: _shadow(color, opacity * _below, fromTop: false),
            ),
        ],
      ),
    );
  }

  Widget _shadow(Color color, double opacity, {required bool fromTop}) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

}
