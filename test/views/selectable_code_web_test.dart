@TestOn('browser')
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/views/components/lesson/selectable_code.dart';

/// Throws the page's one switch the way `BrowserMenuSuppressor` does. The
/// channel is answered here, because the test has no engine to answer it.
Future<void> _browserMenu(WidgetTester tester, {required bool enabled}) => tester.runAsync(
  () => enabled ? BrowserContextMenu.enableContextMenu() : BrowserContextMenu.disableContextMenu(),
);

void main() {
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.contextMenu,
      (_) async => null,
    ),
  );

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.contextMenu,
      null,
    ),
  );

  testWidgets('survives the browser menu being switched while it is on screen', (tester) async {
    Widget code(String text) => Directionality(
      textDirection: TextDirection.ltr,
      child: Overlay.wrap(child: SelectableCode(child: Text(text))),
    );

    // A catalog card turns the menu off while the pointer is over it, and the
    // lesson it opens is built before the pointer moves off the card.
    await _browserMenu(tester, enabled: false);
    await tester.pumpWidget(code('print(1)'));
    await _browserMenu(tester, enabled: true);

    // Any rebuild of the sample after that, which pressing Run is.
    await tester.pumpWidget(code('print(2)'));

    expect(tester.takeException(), isNull);
    // A test runs as Android unless told otherwise, and there the region never
    // uses the browser's menu, which is the switch this is about.
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
