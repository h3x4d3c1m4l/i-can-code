import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/loading_overlay.dart';
import 'package:i_can_code/views/components/progress_ring.dart';

void main() {
  Widget host(Widget child) => Directionality(
    textDirection: TextDirection.ltr,
    child: FTheme(
      data: buildAppTheme(),
      child: Center(child: child),
    ),
  );

  testWidgets('with a value it is a ring that says how far along it is', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const ProgressRing(value: 0.4)));
    await tester.pumpAndSettle();

    expect(find.byType(FCircularProgress), findsNothing);
    expect(find.semantics.byValue('40%'), findsOne);
    semantics.dispose();
  });

  testWidgets('without a value it is the spinner', (tester) async {
    await tester.pumpWidget(host(const ProgressRing(value: null)));

    expect(find.byType(FCircularProgress), findsOneWidget);
  });

  testWidgets('a value arriving does not move what stands beside it', (tester) async {
    await tester.pumpWidget(host(const ProgressRing(value: null)));
    final spinning = tester.getSize(find.byType(ProgressRing));

    await tester.pumpWidget(host(const ProgressRing(value: 0.4)));

    expect(tester.getSize(find.byType(ProgressRing)), spinning);
  });

  testWidgets('a value past either end is drawn as that end', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const ProgressRing(value: 1.7)));
    await tester.pumpAndSettle();

    expect(find.semantics.byValue('100%'), findsOne);
    semantics.dispose();
  });

  testWidgets('the loading card hands its progress to the ring', (tester) async {
    await tester.pumpWidget(host(const LoadingOverlay(message: 'Loading', progress: 0.25)));

    expect(tester.widget<ProgressRing>(find.byType(ProgressRing)).value, 0.25);
  });
}
