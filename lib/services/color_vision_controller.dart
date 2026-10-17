import 'package:mobx/mobx.dart';

part 'color_vision_controller.g.dart';

class ColorVisionController = ColorVisionControllerBase with _$ColorVisionController;

/// A colour vision deficiency the window can be drawn as, at full severity only.
///
/// The three dichromacies are Machado et al.'s matrices for severity 1.0, from
/// [A Physiologically-based Model for Simulation of Color Vision Deficiency](https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html).
/// Every matrix works on *linear* RGB, so it MUST be applied between a
/// conversion out of sRGB gamma and one back into it.
enum ColorVisionDeficiency {

  none(null),

  protanopia([
    0.152286, 1.052583, -0.204868, 0, 0,
    0.114503, 0.786281, 0.099216, 0, 0,
    -0.003882, -0.048116, 1.051998, 0, 0,
    0, 0, 0, 1, 0,
  ]),

  deuteranopia([
    0.367322, 0.860646, -0.227968, 0, 0,
    0.280085, 0.672501, 0.047413, 0, 0,
    -0.011820, 0.042940, 0.968881, 0, 0,
    0, 0, 0, 1, 0,
  ]),

  tritanopia([
    1.255528, -0.076749, -0.178779, 0, 0,
    -0.078411, 0.930809, 0.147602, 0, 0,
    0.004733, 0.691367, 0.303900, 0, 0,
    0, 0, 0, 1, 0,
  ]),

  /// No colour at all: every channel becomes the relative luminance, with the
  /// Rec. 709 weights that sRGB's primaries share.
  achromatopsia([
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  /// A 5×4 matrix in the form `ColorFilter.matrix` takes, or null for none.
  final List<double>? matrix;

  const ColorVisionDeficiency(this.matrix);

}

/// Which deficiency the window is drawn as, picked in the debug menu.
///
/// Not persisted: a reload draws the real colours again, so a simulation left
/// on cannot pass for the app's own palette on the next visit.
abstract class ColorVisionControllerBase with Store {

  @readonly
  ColorVisionDeficiency _deficiency = ColorVisionDeficiency.none;

  @action
  void simulate(ColorVisionDeficiency deficiency) => _deficiency = deficiency;

}
