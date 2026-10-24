import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:i_can_code/views/components/guttered_scroll_view.dart';
import 'package:i_can_code/views/components/split_page.dart';

const Key _left = ValueKey('left');
const Key _right = ValueKey('right');
const Key _leftView = ValueKey('left view');
const Key _rightView = ValueKey('right view');

const double _maxWidth = 1000;
const double _padding = 32;
const double _gap = 36;

Widget _page(double width) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: MediaQueryData(size: Size(width, 600)),
    child: const SplitPage(
      maxWidth: _maxWidth,
      padding: EdgeInsets.symmetric(horizontal: _padding),
      gap: _gap,
      left: GutteredScrollView(key: _leftView, child: SizedBox(key: _left, height: 2000)),
      right: GutteredScrollView(key: _rightView, child: SizedBox(key: _right, height: 2000)),
    ),
  ),
);

/// Where the two columns' content lay before they had a gutter: two even
/// halves of a centred page, [_gap] apart.
(Rect, Rect) _withoutGutter(double width, Size size) {
  final page = (width - 2 * _padding).clamp(0.0, _maxWidth);
  final start = _padding + (width - 2 * _padding - page) / 2;
  final column = (page - _gap) / 2;

  return (
    Rect.fromLTWH(start, 0, column, size.height),
    Rect.fromLTWH(start + column + _gap, 0, column, size.height),
  );
}

void main() {
  for (final width in [1440.0, 800.0]) {
    testWidgets('at $width wide, the content lands where it did without a gutter', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_page(width));

      final (left, right) = _withoutGutter(width, const Size(0, 2000));
      expect(tester.getRect(find.byKey(_left)), left);
      expect(tester.getRect(find.byKey(_right)), right);
    });

    testWidgets('at $width wide, each scrollbar has its room beside the content', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_page(width));

      for (final (view, content) in [(_leftView, _left), (_rightView, _right)]) {
        final gutter = tester.getRect(find.byKey(view)).right - tester.getRect(find.byKey(content)).right;
        expect(gutter, AppScrollbar.gutter);
      }
    });
  }
}
