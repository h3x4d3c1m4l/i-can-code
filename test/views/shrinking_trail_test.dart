import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/views/components/shrinking_trail.dart';

/// A crumb that wants [width] and takes less when it is given less, the way a
/// one-line text with an ellipsis does.
Widget _crumb(String name, double width) => SizedBox(key: ValueKey(name), width: width, height: 20);

const double _dividerWidth = 10;

/// Three crumbs wanting 60, 140 and 100, in a trail [width] wide. With its two
/// dividers it wants 320.
Widget _trail(double width, {double minCrumbWidth = 0}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.topLeft,
        child: ShrinkingTrail(
          minCrumbWidth: minCrumbWidth,
          divider: const SizedBox(width: _dividerWidth, height: 10),
          crumbs: [_crumb('short', 60), _crumb('long', 140), _crumb('last', 100)],
        ),
      ),
    ),
  ),
);

final Finder _dividers = find.byWidgetPredicate((widget) => widget is SizedBox && widget.width == _dividerWidth);

void main() {
  double widthOf(WidgetTester tester, String name) => tester.getSize(find.byKey(ValueKey(name))).width;

  testWidgets('a trail that fits leaves every crumb the width it wants', (tester) async {
    await tester.pumpWidget(_trail(400));

    expect(widthOf(tester, 'short'), 60);
    expect(widthOf(tester, 'long'), 140);
    expect(widthOf(tester, 'last'), 100);
    expect(tester.getSize(find.byType(ShrinkingTrail)).width, 320);
  });

  testWidgets('the widest crumb gives up room first, and a short one keeps its own', (tester) async {
    // 40 short of what it wants, which a Row of Flexibles would have taken
    // out of every crumb alike.
    await tester.pumpWidget(_trail(280));

    expect(widthOf(tester, 'long'), 100);
    expect(widthOf(tester, 'short'), 60);
    expect(widthOf(tester, 'last'), 100);
  });

  testWidgets('crumbs that have been levelled give up the rest together', (tester) async {
    await tester.pumpWidget(_trail(200));

    expect(widthOf(tester, 'long'), 40);
    expect(widthOf(tester, 'short'), 40);
    expect(widthOf(tester, 'last'), 100, reason: 'where the reader is, so the last to lose anything');
    expect(tester.getSize(find.byType(ShrinkingTrail)).width, 200);
  });

  testWidgets('the last crumb is narrowed only once the others have nothing left', (tester) async {
    await tester.pumpWidget(_trail(90));

    expect(widthOf(tester, 'long'), 0);
    expect(widthOf(tester, 'short'), 0);
    expect(widthOf(tester, 'last'), 90 - 2 * _dividerWidth, reason: 'the dividers keep their width');
  });

  testWidgets('the others stop at the least a crumb can say, and the last gives up the rest', (tester) async {
    // 170 short. Down to 30 each, the others free 140 of it.
    await tester.pumpWidget(_trail(150, minCrumbWidth: 30));

    expect(widthOf(tester, 'long'), 30);
    expect(widthOf(tester, 'short'), 30);
    expect(widthOf(tester, 'last'), 70);
  });

  testWidgets('where even that does not fit, the first crumb leaves and the rest take its room', (tester) async {
    // Three crumbs at 30 and two dividers want 110. Without the first crumb
    // and its divider, the other two share 70.
    await tester.pumpWidget(_trail(80, minCrumbWidth: 30));

    expect(tester.getSize(find.byKey(const ValueKey('short'))), Size.zero);
    expect(tester.getSize(_dividers.first), Size.zero, reason: 'a divider with no crumb before it goes too');
    expect(widthOf(tester, 'long'), 30);
    expect(widthOf(tester, 'last'), 40);
    expect(tester.getTopLeft(find.byKey(const ValueKey('long'))).dx, 0);
    expect(tester.getSize(find.byType(ShrinkingTrail)).width, 80);
  });

  testWidgets('left alone, the last crumb takes whatever there is', (tester) async {
    await tester.pumpWidget(_trail(25, minCrumbWidth: 30));

    expect(widthOf(tester, 'short'), 0);
    expect(widthOf(tester, 'long'), 0);
    expect(widthOf(tester, 'last'), 25);
    expect(tester.getTopLeft(find.byKey(const ValueKey('last'))).dx, 0);
  });

  testWidgets('crumbs stand in order, centred on the tallest', (tester) async {
    await tester.pumpWidget(_trail(400));

    expect(tester.getTopLeft(find.byKey(const ValueKey('short'))), Offset.zero);
    expect(tester.getTopLeft(find.byKey(const ValueKey('long'))).dx, 60 + _dividerWidth);
    expect(tester.getTopLeft(find.byKey(const ValueKey('last'))).dx, 60 + 140 + 2 * _dividerWidth);
    // The dividers are 10 tall in a row of 20.
    expect(tester.getTopLeft(_dividers.first), const Offset(60, 5));
  });
}
