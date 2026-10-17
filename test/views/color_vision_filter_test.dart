import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/color_vision_controller.dart';
import 'package:i_can_code/views/components/color_vision_filter.dart';

class _Probe extends StatefulWidget {

  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();

}

class _ProbeState extends State<_Probe> {

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

}

int _filterLayers(WidgetTester tester) => tester.layers.whereType<ColorFilterLayer>().length;

void main() {
  late ColorVisionController colorVision;

  setUp(() => GetIt.I.registerSingleton<ColorVisionController>(colorVision = ColorVisionController()));

  tearDown(GetIt.I.reset);

  testWidgets('composites nothing while no simulation is on', (tester) async {
    await tester.pumpWidget(const ColorVisionFilter(child: _Probe()));

    expect(_filterLayers(tester), 0);
  });

  testWidgets('switching a simulation on and off keeps everything under it', (tester) async {
    await tester.pumpWidget(const ColorVisionFilter(child: _Probe()));
    final before = tester.state(find.byType(_Probe));

    colorVision.simulate(ColorVisionDeficiency.deuteranopia);
    await tester.pump();

    // Out of gamma, the matrix, and back.
    expect(_filterLayers(tester), 3);
    // A wrapper that came and went would rebuild the page, and the dialog the
    // simulation was picked in, from nothing.
    expect(tester.state(find.byType(_Probe)), same(before));

    colorVision.simulate(ColorVisionDeficiency.none);
    await tester.pump();

    expect(_filterLayers(tester), 0);
    expect(tester.state(find.byType(_Probe)), same(before));
  });
}
