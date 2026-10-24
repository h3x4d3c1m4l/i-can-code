import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:i_can_code/views/components/guttered_scroll_view.dart';

const Key _view = ValueKey('view');
const Key _content = ValueKey('content');

/// The app's scroll behaviour round [child], the way the shell puts it round
/// the whole app.
Widget _host(Widget child, {ScrollSurface surface = ScrollSurface.page}) => FTheme(
  data: buildAppTheme(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: ScrollConfiguration(behavior: AppScrollBehavior(surface: surface), child: child),
    ),
  ),
);

/// A page twenty screens tall, so the thumb is short and has far to go.
Widget _longPage() => ListView(key: _view, children: [for (var row = 0; row < 120; row++) const SizedBox(height: 100)]);

ScrollbarPainter _painter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.descendant(of: find.byType(AppScrollbar), matching: find.byType(CustomPaint)).first,
  );
  return paint.foregroundPainter! as ScrollbarPainter;
}

/// Lets the thumb fade in after a scroll. Its fade starts counting on the first
/// frame, so one pump leaves it transparent, and a transparent thumb is never
/// hit.
Future<void> _settleThumb(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Whether the thumb is under [y], in the middle of the bar's width.
bool _thumbAt(WidgetTester tester, double y) {
  final size = tester.getSize(find.byKey(_view));
  return _painter(tester).hitTestOnlyThumbInteractive(
    Offset(size.width - AppScrollbar.gutter / 2, y),
    PointerDeviceKind.mouse,
  );
}

void main() {
  testWidgets('a desktop draws the app\'s scrollbar', (tester) async {
    await tester.pumpWidget(_host(_longPage()));

    expect(find.byType(AppScrollbar), findsOneWidget);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('a touch screen draws none, as Flutter\'s own does', (tester) async {
    await tester.pumpWidget(_host(_longPage()));

    expect(find.byType(AppScrollbar), findsNothing);
  }, variant: TargetPlatformVariant.mobile());

  testWidgets('the thumb keeps clear of both ends and still reaches them', (tester) async {
    await tester.pumpWidget(_host(_longPage()));
    final height = tester.getSize(find.byKey(_view)).height;

    // Scrolled to the top: the thumb is there, but not against the edge.
    await tester.drag(find.byKey(_view), const Offset(0, -10));
    await tester.drag(find.byKey(_view), const Offset(0, 10));
    await _settleThumb(tester);
    expect(_thumbAt(tester, 1), isFalse);
    expect(_thumbAt(tester, 30), isTrue);

    // And at the very end, the same at the bottom.
    final position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    position.jumpTo(position.maxScrollExtent);
    await _settleThumb(tester);
    expect(_thumbAt(tester, height - 1), isFalse);
    expect(_thumbAt(tester, height - 30), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('the thumb takes the ink of the surface it is drawn on', (tester) async {
    await tester.pumpWidget(_host(_longPage()));
    final context = tester.element(find.byKey(_view));
    expect(_painter(tester).color, context.theme.colors.mutedForeground);

    // The page's ink does not show on the code surface, which is dark in every
    // preset.
    await tester.pumpWidget(_host(_longPage(), surface: ScrollSurface.code));
    expect(_painter(tester).color, context.appTheme.colors.codeMuted);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('with no bar over the page, the track starts at the top', (tester) async {
    await tester.pumpWidget(_host(_longPage()));
    await tester.pump();

    expect(_painter(tester).padding.resolve(TextDirection.ltr).top, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a vertical guttered view leaves the bar its room at the end', (tester) async {
    await tester.pumpWidget(
      _host(
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: GutteredScrollView(
              key: _view,
              padding: EdgeInsets.all(10),
              child: SizedBox(key: _content, height: 2000),
            ),
          ),
        ),
      ),
    );

    final view = tester.getRect(find.byKey(_view));
    final content = tester.getRect(find.byKey(_content));
    expect(content.left - view.left, 10);
    expect(view.right - content.right, 10 + AppScrollbar.gutter);
  });

  testWidgets('a horizontal guttered view leaves the bar its room underneath', (tester) async {
    await tester.pumpWidget(
      _host(
        const Align(
          alignment: Alignment.topLeft,
          child: GutteredScrollView(
            key: _view,
            scrollDirection: Axis.horizontal,
            child: SizedBox(key: _content, width: 2000, height: 40),
          ),
        ),
      ),
    );

    final view = tester.getRect(find.byKey(_view));
    final content = tester.getRect(find.byKey(_content));
    expect(content.top, view.top);
    expect(view.bottom - content.bottom, AppScrollbar.gutter);
  });
}
