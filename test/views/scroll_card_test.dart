import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:i_can_code/views/components/scroll_card.dart';

Widget _host({ScrollSurface surface = ScrollSurface.page}) => FTheme(
  data: buildAppTheme(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: 300,
        child: ScrollCard(
          surface: surface,
          child: Column(children: [for (var row = 0; row < 20; row++) const SizedBox(height: 50)]),
        ),
      ),
    ),
  ),
);

ContinuousRectangleBorder _shape(WidgetTester tester) {
  final card = tester.widget<DecoratedBox>(
    find.descendant(of: find.byType(ScrollCard), matching: find.byType(DecoratedBox)).first,
  );
  return (card.decoration as ShapeDecoration).shape as ContinuousRectangleBorder;
}

void main() {
  // Cut off by a straight line, the content stood out past the card's corners.
  testWidgets('cuts what scrolls off at its own rounded edge', (tester) async {
    await tester.pumpWidget(_host());

    final clip = tester.widget<ClipPath>(find.descendant(of: find.byType(ScrollCard), matching: find.byType(ClipPath)));
    expect((clip.clipper! as ShapeBorderClipper).shape, _shape(tester));
  });

  testWidgets('edges a card on the page, and leaves a code card without an edge like every code card', (tester) async {
    await tester.pumpWidget(_host());
    expect(_shape(tester).side, isNot(BorderSide.none));

    await tester.pumpWidget(_host(surface: ScrollSurface.code));
    expect(_shape(tester).side, BorderSide.none);
  });

  testWidgets('shows its thumb at rest', variant: TargetPlatformVariant.only(TargetPlatform.macOS), (tester) async {
    await tester.pumpWidget(_host());

    expect(tester.widget<AppScrollbar>(find.byType(AppScrollbar)).thumbVisibility, isTrue);
  });
}
