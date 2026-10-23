import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/icons/icon_bundle.dart';

void main() {
  test('reads back what was written, each icon under its own key', () {
    final written = IconBundle.encode({
      'loop': Uint8List.fromList([1, 2, 3]),
      'bar-chart': Uint8List(0),
      'dice': Uint8List.fromList(List.filled(300, 7)),
    });
    final bundle = IconBundle.decode(ByteData.sublistView(written));

    expect(bundle.keys, ['loop', 'bar-chart', 'dice']);
    expect(Uint8List.sublistView(bundle['loop']!), [1, 2, 3]);
    expect(bundle['bar-chart']!.lengthInBytes, 0);
    expect(Uint8List.sublistView(bundle['dice']!), List.filled(300, 7));
    expect(bundle['snake'], isNull);
  });

  test('refuses a bundle cut short, or one with bytes past its last icon', () {
    final written = IconBundle.encode({'loop': Uint8List.fromList([1, 2, 3])});

    expect(
      () => IconBundle.decode(ByteData.sublistView(written, 0, written.length - 1)),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => IconBundle.decode(ByteData.sublistView(Uint8List.fromList([...written, 0]))),
      throwsA(isA<FormatException>()),
    );
  });
}
