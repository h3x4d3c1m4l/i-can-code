import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/startup_curtain.dart';

/// A curtain over a page that says [page], the way the shell puts one over
/// the router.
Widget _host(ValueNotifier<String> page, {bool disableAnimations = false, VoidCallback? onOpened}) => FTheme(
  data: buildAppTheme(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(size: const Size(800, 600), disableAnimations: disableAnimations),
      child: StartupCurtain(
        onOpened: onOpened,
        child: ValueListenableBuilder(
          valueListenable: page,
          builder: (context, text, _) => Center(child: Text(text, key: const ValueKey('page'))),
        ),
      ),
    ),
  ),
);

StartupCurtainState _curtain(WidgetTester tester) => tester.state(find.byType(StartupCurtain));

/// Every layer the curtain composites for blurring or fading something.
Iterable<Layer> _effectLayers(WidgetTester tester) sync* {
  Iterable<Layer> walk(Layer layer) sync* {
    yield layer;
    if (layer is ContainerLayer) {
      for (Layer? child = layer.firstChild; child != null; child = child.nextSibling) {
        yield* walk(child);
      }
    }
  }

  yield* walk(tester.layers.first).where((layer) => layer is OpacityLayer || layer is ImageFilterLayer);
}

void main() {
  testWidgets('composites nothing while nothing is playing', (tester) async {
    await tester.pumpWidget(_host(ValueNotifier('loading')));

    expect(find.byType(RawImage), findsNothing);
    expect(_effectLayers(tester), isEmpty);
  });

  testWidgets('swaps the page under a still of the old one, then opens onto it', (tester) async {
    final page = ValueNotifier('loading');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page));

    var lifted = false;
    unawaited(_curtain(tester).lift(() async => page.value = 'home').then((_) => lifted = true));

    // The still goes up after the frame in flight, and only once it is on
    // screen does anything change under it.
    await tester.pump();
    await tester.pump();
    expect(find.byType(RawImage), findsOneWidget);
    expect(find.text('loading'), findsOneWidget);
    expect(find.text('home'), findsNothing);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('home'), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget, reason: 'still opening');
    expect(_effectLayers(tester), isNotEmpty);
    expect(lifted, isFalse);

    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(_effectLayers(tester), isEmpty, reason: 'the app comes to rest exactly as it is');
    expect(lifted, isTrue);
  });

  testWidgets('the page under it keeps its state', (tester) async {
    final page = ValueNotifier('loading');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page));
    final before = tester.element(find.byKey(const ValueKey('page')));

    unawaited(_curtain(tester).lift(() async => page.value = 'home'));
    await tester.pumpAndSettle();

    expect(
      tester.element(find.byKey(const ValueKey('page'))),
      same(before),
      reason: 'a wrapper put in for the transition would build the router again from nothing',
    );
  });

  testWidgets('a press while it opens does not reach the page', (tester) async {
    final page = ValueNotifier('loading');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page));

    unawaited(_curtain(tester).lift(() async => page.value = 'home'));
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('home'), findsOneWidget);
    expect(find.text('home').hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('home').hitTestable(), findsOneWidget);
  });

  testWidgets('says it has opened once it is gone, and only then', (tester) async {
    final page = ValueNotifier('loading');
    addTearDown(page.dispose);
    var opened = 0;
    await tester.pumpWidget(_host(page, onOpened: () => opened++));

    unawaited(_curtain(tester).lift(() async => page.value = 'home'));
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 250));
    expect(opened, 0, reason: 'the page splash shows through until the app is on screen');

    await tester.pumpAndSettle();
    expect(find.byType(RawImage), findsNothing);
    expect(opened, 1);
  });

  testWidgets('reduced motion never says it has opened, because it never played', (tester) async {
    final page = ValueNotifier('loading');
    addTearDown(page.dispose);
    var opened = 0;
    await tester.pumpWidget(_host(page, disableAnimations: true, onOpened: () => opened++));

    unawaited(_curtain(tester).lift(() async => page.value = 'home'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(opened, 0);
  });

  testWidgets('reduced motion swaps at once, with no curtain', (tester) async {
    final page = ValueNotifier('loading');
    addTearDown(page.dispose);
    await tester.pumpWidget(_host(page, disableAnimations: true));

    var lifted = false;
    unawaited(_curtain(tester).lift(() async => page.value = 'home').then((_) => lifted = true));
    await tester.pump();

    expect(find.text('home'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(lifted, isTrue);
  });
}
