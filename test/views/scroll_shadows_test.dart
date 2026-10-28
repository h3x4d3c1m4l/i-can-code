import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:i_can_code/views/components/scroll_shadows.dart';

const double _height = 300;

Widget _host({required int rows, ScrollSurface surface = ScrollSurface.page}) => FTheme(
  data: buildAppTheme(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 400,
        height: _height,
        child: ScrollShadows(
          surface: surface,
          child: ListView(children: [for (var row = 0; row < rows; row++) const SizedBox(height: 50)]),
        ),
      ),
    ),
  ),
);

/// The strength of each shadow drawn, keyed by the edge it stands on.
Map<String, double> _shadows(WidgetTester tester) {
  final boxes = find.descendant(of: find.byType(ScrollShadows), matching: find.byType(DecoratedBox));
  return {
    for (final element in boxes.evaluate())
      if ((element.widget as DecoratedBox).decoration case BoxDecoration(gradient: LinearGradient(:final colors)))
        tester.getRect(find.byWidget(element.widget)).top == 0 ? 'top' : 'bottom': colors.first.a,
  };
}

ScrollPosition _position(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable)).position;

void main() {
  testWidgets('a list that fits draws none', (tester) async {
    await tester.pumpWidget(_host(rows: 3));
    await tester.pump();

    expect(_shadows(tester), isEmpty);
  });

  testWidgets('a list that runs on shows a shadow at the bottom from the start', (tester) async {
    await tester.pumpWidget(_host(rows: 20));
    await tester.pump();

    expect(_shadows(tester).keys, ['bottom']);
  });

  testWidgets('scrolled into the middle, both ends have one, and at the end only the top', (tester) async {
    await tester.pumpWidget(_host(rows: 20));
    await tester.pump();

    _position(tester).jumpTo(200);
    await tester.pump();
    expect(_shadows(tester).keys, unorderedEquals(['top', 'bottom']));

    _position(tester).jumpTo(_position(tester).maxScrollExtent);
    await tester.pump();
    expect(_shadows(tester).keys, ['top']);
  });

  testWidgets('a shadow grows in with the first pixels scrolled past', (tester) async {
    await tester.pumpWidget(_host(rows: 20));
    await tester.pump();

    _position(tester).jumpTo(6);
    await tester.pump();
    final faint = _shadows(tester)['top']!;

    _position(tester).jumpTo(100);
    await tester.pump();
    final full = _shadows(tester)['top']!;

    expect(faint, greaterThan(0));
    expect(faint, lessThan(full));
  });

  // A darker shade does not show on the code surface, so the content fades
  // into it instead.
  testWidgets('on code, the content fades into the surface', (tester) async {
    await tester.pumpWidget(_host(rows: 20, surface: ScrollSurface.code));
    await tester.pump();

    final gradient = tester.widget<DecoratedBox>(
      find.descendant(of: find.byType(ScrollShadows), matching: find.byType(DecoratedBox)),
    );
    final colors = ((gradient.decoration as BoxDecoration).gradient! as LinearGradient).colors;
    final surface = tester.element(find.byType(ScrollShadows)).appTheme.colors.codeBackground;
    expect(colors.first, surface.withValues(alpha: 1));
  });
}
