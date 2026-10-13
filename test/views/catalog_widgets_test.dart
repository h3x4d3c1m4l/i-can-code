import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/routing/catalog_anchor.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/catalog_screen/components/anchor_target.dart';
import 'package:i_can_code/views/catalog_screen/components/catalog_anchor_scope.dart';
import 'package:i_can_code/views/components/catalog_group_heading.dart';
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

  group('AnchorTarget', () {
    const CatalogAnchor here = (kind: CatalogAnchorKind.group, id: 'week-1');
    const size = Size(200, 60);
    // On the middle of the box's left edge: a little way out, and a long way.
    const near = Offset(-1, 30);
    const far = Offset(-20, 30);

    /// A box a screenful down the page, which the address asks for.
    Widget page({CatalogAnchor? asked = here, bool lessMotion = false}) => FTheme(
      data: buildAppTheme(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: const Size(800, 600), disableAnimations: lessMotion),
          child: CatalogAnchorScope(
            anchor: asked,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 900),
                  AnchorTarget(anchor: here, radius: 8, child: SizedBox.fromSize(size: size)),
                  const SizedBox(height: 900),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    RenderObject ring(WidgetTester tester) =>
        tester.renderObject(find.descendant(of: find.byType(AnchorTarget), matching: find.byType(CustomPaint)));

    /// Up to the frame the ring starts on. A scroll is over once its time has
    /// passed, not as it runs out, hence the millisecond.
    Future<void> arrive(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(AnchorTarget.scrollDuration + const Duration(milliseconds: 1));
    }

    testWidgets('draws nothing until the page has come to rest on it', (tester) async {
      await tester.pumpWidget(page());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(ring(tester), paintsNothing, reason: 'a ring over a part that is still moving points at nothing');
    });

    testWidgets('then sends a ring outward from its edge, twice, and is done', (tester) async {
      await tester.pumpWidget(page());
      await arrive(tester);
      final half = CatalogAnchorScope.ringDuration ~/ 2;

      for (var round = 0; round < 2; round++) {
        await tester.pump(const Duration(milliseconds: 60));
        expect(
          ring(tester),
          paints..path(style: PaintingStyle.stroke, includes: [near], excludes: [far]),
          reason: 'ring ${round + 1} starts at the edge',
        );

        await tester.pump(half - const Duration(milliseconds: 120));
        expect(
          ring(tester),
          paints..path(style: PaintingStyle.stroke, includes: [near, const Offset(-8, 30)], excludes: [far]),
          reason: 'ring ${round + 1} has run outward',
        );
        await tester.pump(const Duration(milliseconds: 60));
      }

      await tester.pump(const Duration(milliseconds: 60));
      expect(ring(tester), paintsNothing);
    });

    testWidgets('holds one ring still for a reader who asked for less motion', (tester) async {
      await tester.pumpWidget(page(lessMotion: true));
      await tester.pump();
      await tester.pump();

      for (final wait in const [Duration(milliseconds: 60), Duration(milliseconds: 900)]) {
        await tester.pump(wait);
        expect(
          ring(tester),
          paints..path(style: PaintingStyle.stroke, includes: [near], excludes: [const Offset(-8, 30)]),
          reason: 'after $wait',
        );
      }

      await tester.pump(CatalogAnchorScope.reducedHold);
      expect(ring(tester), paintsNothing);
    });

    testWidgets('stays as it is for an address that asks for another part, or for none', (tester) async {
      for (final asked in <CatalogAnchor?>[null, (kind: CatalogAnchorKind.lesson, id: 'week-1')]) {
        await tester.pumpWidget(page(asked: asked));
        await arrive(tester);
        await tester.pump(const Duration(milliseconds: 60));

        expect(ring(tester), paintsNothing, reason: '$asked');
        expect(tester.hasRunningAnimations, isFalse, reason: '$asked');
      }
    });

    testWidgets('is a plain wrapper where nothing asks at all', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: AnchorTarget(anchor: here, radius: 8, child: SizedBox(width: 200, height: 60))),
        ),
      );

      expect(tester.getSize(find.byType(AnchorTarget)), size);
      expect(ring(tester), paintsNothing);
    });
  });

  group('CatalogGroupHeading', () {
    testWidgets('names its group in capitals, as a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const CatalogGroupHeading('Week 1 · De basis')));
      await tester.pumpAndSettle();

      expect(find.text('WEEK 1 · DE BASIS'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('WEEK 1 · DE BASIS')),
        matchesSemantics(label: 'WEEK 1 · DE BASIS', isHeader: true),
        reason: 'a screen reader can jump between groups by heading',
      );

      handle.dispose();
    });
  });
}
