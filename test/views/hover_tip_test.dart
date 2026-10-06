import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/hover_tip.dart';

/// The app theme and the [Overlay] a tip is drawn in. The app has one above
/// every screen; see `OverlayHost`.
Widget _host(Widget child) => FTheme(
  data: buildAppTheme(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: Overlay(
        initialEntries: [OverlayEntry(builder: (_) => Center(child: child))],
      ),
    ),
  ),
);

/// Something to hover and press. Painted, because a box that paints nothing
/// takes no pointer and the press would never reach the tip around it.
const Widget _tipped = HoverTip(
  message: '4. Lijsten',
  child: ColoredBox(
    key: ValueKey('target'),
    color: Color(0xFF000000),
    child: SizedBox.square(dimension: 40),
  ),
);

/// Moves a mouse onto [target] and lets the tip come up.
Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.pump();
  await mouse.moveTo(tester.getCenter(target));
  // forui waits out its dwell time with a `Future.delayed`, even one of zero,
  // which schedules no frame for pumpAndSettle to find.
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pumpAndSettle();

  return mouse;
}

void main() {
  group('HoverTip', () {
    testWidgets('says its message the moment the pointer is over the child', (tester) async {
      await tester.pumpWidget(_host(_tipped));
      await tester.pumpAndSettle();
      expect(find.text('4. Lijsten'), findsNothing);

      await _hover(tester, find.byKey(const ValueKey('target')));

      expect(find.text('4. Lijsten'), findsOneWidget);
    });

    testWidgets('is gone once the child is pressed', (tester) async {
      // The press is a move somewhere else, and the tip named that place: it
      // MUST NOT still be standing when the place is drawn.
      await tester.pumpWidget(_host(_tipped));
      await tester.pumpAndSettle();
      final mouse = await _hover(tester, find.byKey(const ValueKey('target')));

      await mouse.down(tester.getCenter(find.byKey(const ValueKey('target'))));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('4. Lijsten'), findsNothing);
      await mouse.up();
    });

    testWidgets('is drawn as the app\'s squircle', (tester) async {
      await tester.pumpWidget(_host(_tipped));
      await tester.pumpAndSettle();
      await _hover(tester, find.byKey(const ValueKey('target')));

      final box = tester.widget<DecoratedBox>(
        find.ancestor(of: find.text('4. Lijsten'), matching: find.byType(DecoratedBox)).first,
      );
      // The arrow is a decoration around the tip's own.
      final decoration = switch (box.decoration) {
        FPortalArrowDecoration(:final decoration) => decoration,
        final decoration => decoration,
      };

      // forui draws its own superellipse, which is a different curve.
      expect((decoration as ShapeDecoration).shape, isA<ContinuousRectangleBorder>());
    });
  });

  group('AppButton.tip', () {
    testWidgets('a button says where it goes on hover', (tester) async {
      await tester.pumpWidget(
        _host(AppButton(tip: '4. Lijsten', onPress: () {}, child: const Text('Volgende'))),
      );
      await tester.pumpAndSettle();

      await _hover(tester, find.text('Volgende'));

      expect(find.text('4. Lijsten'), findsOneWidget);
    });

    testWidgets('a button held down a moment too long still presses', (tester) async {
      // forui's tooltip opens on a long press by wrapping its child in a
      // recogniser, which takes the press away from the button under it.
      var presses = 0;
      await tester.pumpWidget(
        _host(AppButton(tip: '4. Lijsten', onPress: () => presses++, child: const Text('Volgende'))),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(presses, 1);
    });

    testWidgets('a screen reader is told where it goes as well', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          AppButton.icon(
            icon: FLucideIcons.chevronLeft,
            semanticsLabel: 'Vorige stap',
            tip: '3. Tekst',
            onPress: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSemantics(find.bySemanticsLabel('Vorige stap')).tooltip, '3. Tekst');

      handle.dispose();
    });

    testWidgets('a tip that only repeats the label is not read twice', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          AppButton.icon(
            icon: FLucideIcons.chevronLeft,
            semanticsLabel: 'Terug naar Python',
            tip: 'Terug naar Python',
            onPress: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSemantics(find.bySemanticsLabel('Terug naar Python')).tooltip, isEmpty);

      handle.dispose();
    });

    testWidgets('a button without one is left as it was', (tester) async {
      await tester.pumpWidget(_host(AppButton(onPress: () {}, child: const Text('Volgende'))));
      await tester.pumpAndSettle();

      expect(find.byType(HoverTip), findsNothing);
    });
  });
}
