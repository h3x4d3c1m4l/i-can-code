import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/color_vision_controller.dart';

/// Row [row] of the 3×3 colour part of a 5×4 filter matrix.
List<double> _row(List<double> matrix, int row) => matrix.sublist(row * 5, row * 5 + 3);

void main() {
  test('starts on the real colours', () => expect(ColorVisionController().deficiency, ColorVisionDeficiency.none));

  test('draws nothing at all for none', () => expect(ColorVisionDeficiency.none.matrix, isNull));

  // Every published matrix keeps the neutral axis where it is, so a mistyped
  // digit shows up as a tinted white.
  for (final deficiency in ColorVisionDeficiency.values.where((value) => value.matrix != null)) {
    test('${deficiency.name} leaves white white, black black and alpha alone', () {
      final matrix = deficiency.matrix!;
      expect(matrix, hasLength(20));
      for (var row = 0; row < 3; row++) {
        final sum = _row(matrix, row).reduce((a, b) => a + b);
        expect(sum, closeTo(1, 1e-5), reason: 'row $row');
        expect(matrix[row * 5 + 3], 0, reason: 'row $row reads no alpha');
        expect(matrix[row * 5 + 4], 0, reason: 'row $row adds no offset');
      }
      expect(matrix.sublist(15), [0, 0, 0, 1, 0]);
    });
  }

  test('achromatopsia leaves no colour', () {
    final matrix = ColorVisionDeficiency.achromatopsia.matrix!;
    expect(_row(matrix, 1), _row(matrix, 0));
    expect(_row(matrix, 2), _row(matrix, 0));
  });
}
