import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/hint_mark.dart';

/// What the catalog's widgets need: the app theme, the localizations, and an
/// [Overlay], because a popover is an `OverlayPortal` and throws without one.
/// The app shell puts that overlay above the router, so every screen really
/// does sit under one — see *The bar* in `CLAUDE.md`.
Widget _host(Widget child) => FTheme(
  data: buildAppTheme(),
  child: Localizations(
    locale: const Locale('nl'),
    delegates: AppLocalizations.localizationsDelegates,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: Overlay(
          initialEntries: [OverlayEntry(builder: (_) => Align(child: child))],
        ),
      ),
    ),
  ),
);

const _message = 'Deze lessen gaan verder dan de basisstof.';
const _label = 'Wat is een verdieping?';

Widget get _hint => const HintMark(message: _message, semanticsLabel: _label);

void main() {
  group('HintMark', () {
    testWidgets('keeps the explanation out of the way until it is asked for', (tester) async {
      await tester.pumpWidget(_host(_hint));
      await tester.pumpAndSettle();

      expect(find.byIcon(FLucideIcons.circleQuestionMark), findsOneWidget);
      expect(find.text(_message), findsNothing, reason: 'a sentence that is always there competes with the cards');
    });

    testWidgets('hovering it says so straight away', (tester) async {
      // No dwell time on purpose: forui's tooltip waits out half a second,
      // which on a mark this small reads as nothing happening.
      await tester.pumpWidget(_host(_hint));
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(find.byIcon(FLucideIcons.circleQuestionMark)));
      await tester.pumpAndSettle();

      expect(find.text(_message), findsOneWidget);

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text(_message), findsNothing, reason: 'and stops when the pointer leaves');
    });

    testWidgets('a tap opens the explanation, which is what a touch screen has', (tester) async {
      // Why this is an FPopover rather than an FTooltip: forui's tooltip hides
      // itself on every pointer down, so a tap opens and closes it in one
      // gesture and nothing is ever read.
      await tester.pumpWidget(_host(_hint));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(FLucideIcons.circleQuestionMark));
      await tester.pumpAndSettle();

      expect(find.text(_message), findsOneWidget);
    });

    testWidgets('the mark is a button a screen reader can name', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(_hint));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(_label),
        findsOneWidget,
        reason: 'there is no text inside the mark to fall back on',
      );

      handle.dispose();
    });

    testWidgets('the keyboard can open it, because the mark is a real button', (tester) async {
      // An Icon on its own takes no focus and answers no key. Building the mark
      // on FTappable is what puts it in the tab order and makes Enter press it.
      //
      // Traversal is driven directly rather than by sending Tab: the Tab key is
      // bound by `WidgetsApp`, which this host deliberately does not have.
      await tester.pumpWidget(_host(_hint));
      await tester.pumpAndSettle();

      expect(FocusScope.of(tester.element(find.byType(HintMark))).nextFocus(), isTrue);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text(_message), findsOneWidget);
    });
  });
}
