import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/color_vision_controller.dart';

/// Draws everything under it with the deficiency [ColorVisionController] holds.
///
/// Not a [ColorFiltered] put in and taken out: a wrapper that comes and goes
/// changes the shape of the tree, and Flutter then builds everything under it
/// from nothing, the router's pages and the debug menu's own dialog included.
/// This one is always there and only pushes its layers while a simulation is on.
class ColorVisionFilter extends StatelessWidget {

  final Widget child;

  const ColorVisionFilter({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) => _ColorVisionLayers(
        matrix: GetIt.I<ColorVisionController>().deficiency.matrix,
        child: child,
      ),
    );
  }

}

class _ColorVisionLayers extends SingleChildRenderObjectWidget {

  final List<double>? matrix;

  const _ColorVisionLayers({required this.matrix, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderColorVisionLayers(matrix);

  @override
  void updateRenderObject(BuildContext context, _RenderColorVisionLayers renderObject) {
    renderObject.matrix = matrix;
  }

}

/// [ColorFiltered]'s render object three layers deep, and only while it has a
/// matrix. Without one it paints its child straight through and composites
/// nothing, so a release build pays for no layer while no one is looking.
class _RenderColorVisionLayers extends RenderProxyBox {

  List<double>? _matrix;

  final LayerHandle<ColorFilterLayer> _matrixLayer = LayerHandle();
  final LayerHandle<ColorFilterLayer> _linearLayer = LayerHandle();

  _RenderColorVisionLayers(this._matrix);

  set matrix(List<double>? value) {
    if (identical(value, _matrix)) return;
    final wasFiltering = _matrix != null;
    _matrix = value;
    if (wasFiltering != (value != null)) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _matrix != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final matrix = _matrix;
    if (matrix == null || child == null) {
      _releaseLayers();
      super.paint(context, offset);
      return;
    }

    // Read inside out: the innermost layer is applied first, so the child
    // leaves sRGB's gamma, goes through the matrix, and comes back.
    layer = context.pushColorFilter(
      offset,
      const ColorFilter.linearToSrgbGamma(),
      (context, offset) => _matrixLayer.layer = context.pushColorFilter(
        offset,
        ColorFilter.matrix(matrix),
        (context, offset) => _linearLayer.layer = context.pushColorFilter(
          offset,
          const ColorFilter.srgbToLinearGamma(),
          super.paint,
          oldLayer: _linearLayer.layer,
        ),
        oldLayer: _matrixLayer.layer,
      ),
      oldLayer: layer as ColorFilterLayer?,
    );
  }

  void _releaseLayers() {
    layer = null;
    _matrixLayer.layer = null;
    _linearLayer.layer = null;
  }

  @override
  void dispose() {
    _releaseLayers();
    super.dispose();
  }

}
