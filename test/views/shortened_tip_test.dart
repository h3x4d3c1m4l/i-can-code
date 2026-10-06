import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/shortened_tip.dart';

const String _label = 'Week 1 · De basis';

/// The app theme and the [Overlay] a tip is drawn in.
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

/// A one-line text the way a crumb of the trail sets it.
const Widget _tipped = ShortenedTip(
  message: _label,
  child: Text(_label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
);

/// Moves [mouse] onto [target] and lets a tip come up.
Future<void> _hover(WidgetTester tester, TestGesture mouse, Finder target) async {
  await mouse.moveTo(tester.getCenter(target));
  // forui waits out its dwell time with a `Future.delayed`, even one of zero,
  // which schedules no frame for pumpAndSettle to find.
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pumpAndSettle();
}

/// Moves [mouse] off everything and lets a tip go.
Future<void> _leave(WidgetTester tester, TestGesture mouse) async {
  await mouse.moveTo(Offset.zero);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.pump();

  return mouse;
}

void main() {
  testWidgets('says nothing about a child that has the room it wants', (tester) async {
    // Loose, the way the trail leaves a crumb it did not narrow.
    await tester.pumpWidget(_host(_tipped));
    await tester.pumpAndSettle();
    final mouse = await _mouse(tester);

    await _hover(tester, mouse, find.byType(ShortenedTip));

    expect(find.text(_label), findsOneWidget, reason: 'the text itself, and no tip repeating it');
  });

  testWidgets('says the whole of a child that is cut short', (tester) async {
    await tester.pumpWidget(_host(const SizedBox(width: 60, child: _tipped)));
    await tester.pumpAndSettle();
    final mouse = await _mouse(tester);

    await _hover(tester, mouse, find.byType(ShortenedTip));

    expect(find.text(_label), findsNWidgets(2), reason: 'the text and the tip');
  });

  testWidgets('answers for the room the child has now', (tester) async {
    // A window that grows gives the text its room back. Nothing rebuilds the
    // tip for that, so it MUST be asked on the hover.
    final width = ValueNotifier<double>(60);
    addTearDown(width.dispose);
    await tester.pumpWidget(
      _host(
        ValueListenableBuilder(
          valueListenable: width,
          builder: (_, width, _) => SizedBox(width: width, child: _tipped),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await _mouse(tester);

    await _hover(tester, mouse, find.byType(ShortenedTip));
    expect(find.text(_label), findsNWidgets(2));

    await _leave(tester, mouse);
    width.value = 700;
    await tester.pumpAndSettle();
    await _hover(tester, mouse, find.byType(ShortenedTip));

    expect(find.text(_label), findsOneWidget);
  });
}
