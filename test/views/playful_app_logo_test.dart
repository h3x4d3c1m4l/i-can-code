import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_logo.dart';
import 'package:i_can_code/views/components/playful_app_logo.dart';

Widget _host({bool disableAnimations = false}) => FTheme(
  data: buildAppTheme(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: const Center(child: PlayfulAppLogo()),
    ),
  ),
);

LogoPose _pose(WidgetTester tester) => tester.widget<AppLogo>(find.byType(AppLogo)).pose;

void main() {
  for (final trick in LogoTrick.values) {
    test('$trick starts and ends on the mark as drawn', () {
      expect(trick.poseAt(0), LogoPose.rest);
      expect(trick.poseAt(1), LogoPose.rest);
    });

    test('$trick moves something halfway through', () {
      expect(trick.poseAt(0.5), isNot(LogoPose.rest));
    });
  }

  testWidgets('a press plays a trick and comes back to rest', (tester) async {
    await tester.pumpWidget(_host());
    expect(_pose(tester), LogoPose.rest);

    await tester.tap(find.byType(PlayfulAppLogo));
    // The first frame only starts the ticker.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_pose(tester), isNot(LogoPose.rest));

    await tester.pumpAndSettle();
    expect(_pose(tester), LogoPose.rest);
  });

  testWidgets('reduced motion plays nothing', (tester) async {
    await tester.pumpWidget(_host(disableAnimations: true));

    await tester.tap(find.byType(PlayfulAppLogo));
    await tester.pump();

    expect(_pose(tester), LogoPose.rest);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a screen reader is not told about it', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host());

    expect(tester.getSemantics(find.byType(PlayfulAppLogo)), isNot(matchesSemantics(hasTapAction: true)));
    semantics.dispose();
  });

}
