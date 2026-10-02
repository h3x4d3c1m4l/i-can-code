import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/components/app_logo.dart';

/// Something the header's logo does when it is pressed.
///
/// A press picks one at random, so adding a trick means adding a case here and
/// nothing else.
enum LogoTrick {

  /// The tile crouches, hops and lands, and winks while it is in the air.
  winkAndHop(Duration(milliseconds: 700)),

  /// The smile widens into a grin, the eyes squeeze and the tile swells.
  grin(Duration(milliseconds: 900));

  final Duration duration;

  const LogoTrick(this.duration);

  /// How far the eyes close at a full grin.
  static const double _squint = 0.55;

  /// How much the tile swells at a full grin.
  static const double _swell = 0.12;

  static final _hopLift = TweenSequence([
    _hold(0, 14),
    _ease(0, 0.3, Curves.easeOutCubic, 22),
    _ease(0.3, 0, Curves.easeInCubic, 20),
    _hold(0, 44),
  ]);

  /// Lined up with [_hopLift]: down before the jump, tall on the way up, and
  /// squashed again where it lands.
  static final _hopStretch = TweenSequence([
    _ease(1, 0.86, Curves.easeOut, 14),
    _ease(0.86, 1.08, Curves.easeOut, 10),
    _ease(1.08, 1, Curves.easeInOut, 26),
    _hold(1, 6),
    _ease(1, 0.9, Curves.easeOut, 8),
    _ease(0.9, 1, Curves.easeOutBack, 36),
  ]);

  static final _wink = TweenSequence([
    _hold(1, 24),
    _ease(1, 0, Curves.easeIn, 10),
    _hold(0, 30),
    _ease(0, 1, Curves.easeOut, 12),
    _hold(1, 24),
  ]);

  /// Overshoots a little on the way in, which is the pop.
  static final _grin = TweenSequence([
    _ease(0, 1, Curves.easeOutBack, 22),
    _hold(1, 48),
    _ease(1, 0, Curves.easeInOutCubic, 30),
  ]);

  /// The face at [t], from 0 to 1 over [duration].
  ///
  /// MUST be [LogoPose.rest] at 0 and at 1, because the logo shows this trick's
  /// pose at either end for as long as it is not playing.
  LogoPose poseAt(double t) {
    switch (this) {
      case winkAndHop:
        return LogoPose(rightEye: _wink.transform(t), stretch: _hopStretch.transform(t), lift: _hopLift.transform(t));
      case grin:
        final amount = _grin.transform(t);
        final eyes = 1 - _squint * amount;
        return LogoPose(leftEye: eyes, rightEye: eyes, grin: amount, scale: 1 + _swell * amount);
    }
  }

}

/// One stretch of a [TweenSequence], from [begin] to [end] along [curve].
TweenSequenceItem<double> _ease(double begin, double end, Curve curve, double weight) =>
    TweenSequenceItem(tween: Tween(begin: begin, end: end).chain(CurveTween(curve: curve)), weight: weight);

/// One stretch of a [TweenSequence] that stays at [value].
TweenSequenceItem<double> _hold(double value, double weight) =>
    TweenSequenceItem(tween: ConstantTween(value), weight: weight);

/// The header's [AppLogo], which plays a random [LogoTrick] when pressed.
///
/// An easter egg, so it gives nothing away: no pointer cursor, no tab stop and
/// nothing for a screen reader.
class PlayfulAppLogo extends StatefulWidget {

  const PlayfulAppLogo({super.key});

  @override
  State<PlayfulAppLogo> createState() => _PlayfulAppLogoState();

}

class _PlayfulAppLogoState extends State<PlayfulAppLogo> with SingleTickerProviderStateMixin {

  final _random = math.Random();
  late final _controller = AnimationController(vsync: this);
  LogoTrick _trick = LogoTrick.values.first;

  void _play() {
    // Starting over mid-trick would snap the tile back to rest in one frame.
    if (_controller.isAnimating) return;

    _trick = LogoTrick.values[_random.nextInt(LogoTrick.values.length)];
    _controller
      ..duration = context.motion(_trick.duration)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: _play,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => AppLogo(pose: _trick.poseAt(_controller.value)),
      ),
    );
  }

}
