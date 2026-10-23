import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';

/// The way from the initialization screen into the app, over the whole window:
/// what was on screen zooms towards the reader, blurs and fades, while the app
/// comes up out of a blur underneath it.
///
/// What fades is a snapshot, because the screen it shows is gone by then. The
/// router replaces it with the first page, and that page has to be built and
/// standing before the curtain can open onto it. The curtain sits above
/// `AppHeaderHost`, so the bar arrives with the page instead of on its own.
///
/// Always in the tree and only switched, for the reason `ColorVisionFilter`
/// gives: a wrapper put in for the transition and taken out after would build
/// the router under it from nothing. At rest it composites nothing (see
/// [_CurtainLayers]).
class StartupCurtain extends StatefulWidget {

  final Widget child;

  /// Called once the curtain has opened and is gone, by which time the app has
  /// been on screen for the whole of it. Not called when it was skipped.
  final VoidCallback? onOpened;

  const StartupCurtain({required this.child, this.onOpened, super.key});

  /// Null below no curtain: a widget test that builds a screen and a router of
  /// its own.
  static StartupCurtainState? maybeOf(BuildContext context) => context.findAncestorStateOfType<StartupCurtainState>();

  @override
  State<StartupCurtain> createState() => StartupCurtainState();

}

class StartupCurtainState extends State<StartupCurtain> with SingleTickerProviderStateMixin {

  static const Duration _duration = Duration(milliseconds: 550);

  /// How far the snapshot grows and blurs on its way out.
  static const double _curtainGrowth = 0.1;
  static const double _curtainBlur = 18;

  /// Where the app starts from on its way in.
  static const double _appScale = 0.97;
  static const double _appBlur = 8;

  static const Curve _curtainZoom = Curves.easeInCubic;
  static const Curve _curtainFade = Interval(0, 0.75, curve: Curves.easeIn);
  static const Curve _appArrive = Curves.easeOutCubic;
  static const Curve _appFade = Interval(0.15, 1, curve: Curves.easeOut);

  final GlobalKey _app = GlobalKey();

  /// At 1 when nothing is playing, which is the app as it is.
  late final AnimationController _controller = AnimationController(vsync: this, value: 1);

  ui.Image? _snapshot;

  /// Freezes the window as it is, runs [swap] under it, and opens onto what
  /// [swap] left. Completes once the curtain is gone.
  ///
  /// [swap] runs without a curtain when the reader asked for less motion, or
  /// when a curtain is already up, and [StartupCurtain.onOpened] is then not
  /// called.
  Future<void> lift(Future<void> Function() swap) async {
    final duration = context.motion(_duration);
    if (duration == Duration.zero || _snapshot != null) return swap();

    // The frame in flight may still paint; the snapshot has to come after it.
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted) return swap();

    final boundary = _app.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final snapshot = boundary.toImageSync(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    setState(() => _snapshot = snapshot);
    _controller.value = 0;

    // On screen before anything changes under it.
    await SchedulerBinding.instance.endOfFrame;
    await swap();
    if (!mounted) return;

    _controller.duration = duration;
    await _controller.forward();
    if (!mounted) return;

    setState(() => _snapshot = null);
    snapshot.dispose();
    widget.onOpened?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _controller,
          child: RepaintBoundary(key: _app, child: widget.child),
          builder: (context, child) {
            final t = _controller.value;
            final arrived = _appArrive.transform(t);
            return _CurtainLayers(
              // The page's colour, under an app that is still fading in.
              backdrop: context.theme.colors.background,
              opacity: _appFade.transform(t),
              scale: ui.lerpDouble(_appScale, 1, arrived)!,
              blur: _appBlur * (1 - arrived),
              child: child,
            );
          },
        ),
        if (snapshot != null)
          AbsorbPointer(
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  final zoom = _curtainZoom.transform(t);
                  return _CurtainLayers(
                    opacity: 1 - _curtainFade.transform(t),
                    scale: 1 + _curtainGrowth * zoom,
                    blur: _curtainBlur * zoom,
                    child: RawImage(image: snapshot, scale: MediaQuery.devicePixelRatioOf(context), fit: BoxFit.fill),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

}

/// [child] faded, scaled from its centre and blurred, over [backdrop].
///
/// Not [Opacity], [Transform] and [ImageFiltered] left at rest: [Opacity] keeps
/// an opacity layer at 1 too, and the web engine draws every opacity layer
/// through a `saveLayer` of its own, which around the whole app would cost a
/// window-sized buffer on every frame. This composites nothing at rest.
class _CurtainLayers extends SingleChildRenderObjectWidget {

  final double opacity;
  final double scale;
  final double blur;

  /// Painted under [child] while it is away from rest.
  final Color? backdrop;

  const _CurtainLayers({required this.opacity, required this.scale, required this.blur, this.backdrop, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCurtainLayers(opacity: opacity, scale: scale, blur: blur, backdrop: backdrop);

  @override
  void updateRenderObject(BuildContext context, _RenderCurtainLayers renderObject) {
    renderObject
      ..opacity = opacity
      ..scale = scale
      ..blur = blur
      ..backdrop = backdrop;
  }

}

class _RenderCurtainLayers extends RenderProxyBox {

  double _opacity;
  double _scale;
  double _blur;
  Color? _backdrop;

  final LayerHandle<TransformLayer> _transformLayer = LayerHandle();
  final LayerHandle<ImageFilterLayer> _filterLayer = LayerHandle();

  _RenderCurtainLayers({required this._opacity, required this._scale, required this._blur, this._backdrop});

  bool get _resting => _opacity == 1 && _scale == 1 && _blur == 0;

  set opacity(double value) {
    if (value != _opacity) _change(() => _opacity = value);
  }

  set scale(double value) {
    if (value != _scale) _change(() => _scale = value);
  }

  set blur(double value) {
    if (value != _blur) _change(() => _blur = value);
  }

  set backdrop(Color? value) {
    if (value == _backdrop) return;
    _backdrop = value;
    markNeedsPaint();
  }

  void _change(VoidCallback change) {
    final wasResting = _resting;
    change();
    if (wasResting != _resting) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && !_resting;

  /// [_scale] about the centre.
  Matrix4 get _transform {
    final centre = size.center(Offset.zero);
    return Matrix4.diagonal3Values(_scale, _scale, 1)
      ..setTranslationRaw(centre.dx * (1 - _scale), centre.dy * (1 - _scale), 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _resting) {
      _releaseLayers();
      super.paint(context, offset);
      return;
    }

    if (_backdrop case final Color backdrop) context.canvas.drawRect(offset & size, Paint()..color = backdrop);
    if (_opacity == 0) {
      _releaseLayers();
      return;
    }

    layer = context.pushOpacity(
      offset,
      ui.Color.getAlphaFromOpacity(_opacity),
      (context, offset) => _transformLayer.layer = context.pushTransform(
        needsCompositing,
        offset,
        _transform,
        (context, offset) {
          if (_blur == 0) {
            _filterLayer.layer = null;
            super.paint(context, offset);
            return;
          }
          final filter = (_filterLayer.layer ?? ImageFilterLayer())
            ..imageFilter = ui.ImageFilter.blur(sigmaX: _blur, sigmaY: _blur, tileMode: TileMode.clamp);
          _filterLayer.layer = filter;
          context.pushLayer(filter, super.paint, offset);
        },
        oldLayer: _transformLayer.layer,
      ),
      oldLayer: layer as OpacityLayer?,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _scale == 1 ? null : _transform,
      position: position,
      hitTest: (result, position) => super.hitTestChildren(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_scale != 1) transform.multiply(_transform);
  }

  void _releaseLayers() {
    layer = null;
    _transformLayer.layer = null;
    _filterLayer.layer = null;
  }

  @override
  void dispose() {
    _releaseLayers();
    super.dispose();
  }

}
