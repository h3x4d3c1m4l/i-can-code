import 'package:flutter/widgets.dart';

extension ColorExtension on Color {

  /// This colour with [amount] taken off its [HSLColor] lightness, clamped at
  /// black.
  ///
  /// What a bevelled control draws its edge and collar with, so neither needs a
  /// design token of its own: they are a shade of the surface they sit on, and
  /// move with it between presets.
  Color darken(double amount) {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - amount).clamp(0, 1)).toColor();
  }

}
