import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_logo.dart';
import 'package:i_can_code/views/initialization_screen/components/winking_app_logo.dart';

Widget _host(ValueNotifier<bool> wink, VoidCallback onWinked, {bool disableAnimations = false}) => FTheme(
  data: buildAppTheme(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Center(
        child: ValueListenableBuilder(
          valueListenable: wink,
          builder: (context, wink, _) => WinkingAppLogo(size: 118, wink: wink, onWinked: onWinked),
        ),
      ),
    ),
  ),
);

LogoPose _pose(WidgetTester tester) => tester.widget<AppLogo>(find.byType(AppLogo)).pose;

void main() {
  testWidgets('stays still until it is told to wink', (tester) async {
    var winks = 0;
    await tester.pumpWidget(_host(ValueNotifier(false), () => winks++));
    await tester.pump(const Duration(seconds: 5));

    expect(_pose(tester), LogoPose.rest);
    expect(tester.hasRunningAnimations, isFalse);
    expect(winks, 0);
  });

  testWidgets('winks once, and calls back after the eye has opened again', (tester) async {
    final wink = ValueNotifier(false);
    addTearDown(wink.dispose);
    var winks = 0;
    await tester.pumpWidget(_host(wink, () => winks++));

    wink.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_pose(tester).rightEye, lessThan(1));
    expect(_pose(tester).leftEye, 1, reason: 'a wink, not a blink');
    expect(winks, 0);

    await tester.pumpAndSettle();
    expect(_pose(tester), LogoPose.rest);
    expect(winks, 1);

    await tester.pump(const Duration(seconds: 5));
    expect(winks, 1, reason: 'once, not on a timer');
  });

  testWidgets('a logo that is built already told to wink winks as it arrives', (tester) async {
    var winks = 0;
    await tester.pumpWidget(_host(ValueNotifier(true), () => winks++));
    await tester.pumpAndSettle();

    expect(winks, 1);
  });

  testWidgets('reduced motion calls back at once, without a wink', (tester) async {
    final wink = ValueNotifier(false);
    addTearDown(wink.dispose);
    var winks = 0;
    await tester.pumpWidget(_host(wink, () => winks++, disableAnimations: true));

    wink.value = true;
    await tester.pump();

    expect(_pose(tester), LogoPose.rest);
    expect(tester.hasRunningAnimations, isFalse);
    expect(winks, 1);
  });

  testWidgets('a logo that leaves mid-wink does not call back', (tester) async {
    final wink = ValueNotifier(false);
    addTearDown(wink.dispose);
    var winks = 0;
    await tester.pumpWidget(_host(wink, () => winks++));

    wink.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(winks, 0);
  });
}
