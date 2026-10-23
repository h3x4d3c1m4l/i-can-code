import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/views/components/app_logo.dart';

/// The initialization screen's [AppLogo], which winks once when [wink] turns
/// true and then calls [onWinked].
///
/// [onWinked] is called after the eye has opened again, never during a build,
/// and at once when the reader asked for less motion. It is not called if the
/// logo leaves the tree first.
class WinkingAppLogo extends StatefulWidget {

  final double size;
  final bool wink;
  final VoidCallback onWinked;

  const WinkingAppLogo({required this.size, required this.wink, required this.onWinked, super.key});

  @override
  State<WinkingAppLogo> createState() => _WinkingAppLogoState();

}

class _WinkingAppLogoState extends State<WinkingAppLogo> with SingleTickerProviderStateMixin {

  static const _duration = Duration(milliseconds: 600);

  /// A beat before the eye shuts, so the wink reads as an answer to the ring
  /// filling up, and one after it opens, so the screen does not leave on a
  /// half-open eye.
  static final _rightEye = TweenSequence([
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 24),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 10),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 24),
  ]);

  late final _controller = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here rather than in initState, which cannot read the MediaQuery yet.
    _controller.duration = context.motion(_duration);
    if (widget.wink && _controller.isDismissed) _play();
  }

  @override
  void didUpdateWidget(WinkingAppLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wink && !oldWidget.wink) _play();
  }

  Future<void> _play() async {
    // Awaited even at zero duration, because the future then completes in a
    // microtask and keeps the callback out of the build that started it.
    await _controller.forward(from: 0);
    if (mounted) widget.onWinked();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => AppLogo(size: widget.size, pose: LogoPose(rightEye: _rightEye.transform(_controller.value))),
    );
  }

}
